import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'presence_keys.dart';
import 'presence_socket.dart';
import 'presence_state.dart';

/// Where apps connect: the presence backend's `/v1/app` over `wss`.
Uri presenceAppUrl([String base = kPresenceUrl]) {
  final url = Uri.parse(base);
  return url.replace(
    scheme: url.scheme == 'http' ? 'ws' : 'wss',
    path: '/v1/app',
  );
}

/// A Firebase ID token and when it stops being valid.
typedef PresenceToken = ({String token, DateTime expires});

/// Fetches the account's ID token, a fresh one with [force]; null when no
/// account is signed in.
typedef PresenceTokenSource = Future<PresenceToken?> Function({bool force});

/// Why the connection stopped for good until [LivePresence.setWanted] is
/// toggled: the account has no Pro, its credential was refused, or the
/// client spoke the protocol wrong.
enum PresenceStop { notPro, refused, protocol }

/// Close codes the presence backend uses; see its `docs/protocol.md`.
@visibleForTesting
abstract final class PresenceCloseCode {
  static const badMessage = 4000;
  static const tokenExpired = 4001;
  static const notPro = 4002;
  static const revoked = 4003;
  static const noSubprotocol = 4011;
}

/// Keeps a connection to the presence backend while it is wanted and turns
/// what the backend says into [byProfile]: which of the user's servers are
/// online and, where this device holds the server's key, which sessions they
/// hold.
///
/// Wanted means signed in with Pro and - on a phone - in the foreground; the
/// caller decides and calls [setWanted]. A dropped connection comes back
/// after a growing, jittered delay; one closed for a reason retrying cannot
/// fix (no Pro, a revoked account, a protocol error) stays closed until the
/// caller wants it again. The token is renewed with `reauth` five minutes
/// before it expires.
class LivePresence {
  LivePresence({
    required PresenceConnect connect,
    required PresenceTokenSource token,
    required PresenceKeyStore keys,
    Uri? url,
    Random? random,
    DateTime Function()? now,
  }) : _connect = connect,
       _token = token,
       _keys = keys,
       _url = url ?? presenceAppUrl(),
       _random = random ?? Random(),
       _now = now ?? DateTime.now {
    _keys.changes.addListener(_recompute);
  }

  final PresenceConnect _connect;
  final PresenceTokenSource _token;
  final PresenceKeyStore _keys;
  final Uri _url;
  final Random _random;
  final DateTime Function() _now;

  /// Each server the backend reports, by the profile it belongs to. A server
  /// whose relay key this account cannot place on a profile is left out.
  final byProfile = ValueNotifier<Map<String, ServerPresence>>(const {});

  /// Why the connection stopped for good, or null while it runs or retries.
  final stopped = ValueNotifier<PresenceStop?>(null);

  /// Called with every server whose sessions this device could read, after
  /// each change, so the caller can show them as session rows. The list is
  /// the agent's last report: a server that went offline without saying so
  /// keeps the sessions it last listed, which survive a reboot.
  void Function(Map<String, List<PresenceSession>> sessionsByProfile)?
  onSessions;

  final _raw = <String, ({bool online, String state, int at})>{};
  final _opened = <String, OpenedPresence>{};
  final _freshness = PresenceFreshness();
  Map<String, String> _profileForKey = const {};

  bool _wanted = false;
  PresenceSocket? _socket;
  StreamSubscription<String>? _subscription;
  Timer? _retry;
  Timer? _reauth;
  int _attempt = 0;
  bool _connecting = false;
  bool _forceToken = false;
  int _generation = 0;
  Future<void> _processing = Future.value();

  /// Whether a connection is open right now.
  bool get connected => _socket != null;

  /// Which profile each relay key id belongs to, from the account's relay
  /// keys. Changing it re-reads what the backend last said.
  set profileForKey(Map<String, String> mapping) {
    _profileForKey = Map.unmodifiable(mapping);
    _recompute();
  }

  /// Opens the connection when [wanted] and it is not open; closes it and
  /// forgets everything when not. Wanting it again clears a stop.
  void setWanted(bool wanted) {
    if (wanted == _wanted) {
      if (wanted) _ensureConnected();
      return;
    }
    _wanted = wanted;
    if (wanted) {
      stopped.value = null;
      _attempt = 0;
      _ensureConnected();
    } else {
      _shutDown();
      _raw.clear();
      _opened.clear();
      _freshness.clear();
      byProfile.value = const {};
    }
  }

  /// Tries again now rather than after the backoff - for the network coming
  /// back.
  void retryNow() {
    if (!_wanted || _socket != null || stopped.value != null) return;
    _retry?.cancel();
    _retry = null;
    _ensureConnected();
  }

  void dispose() {
    _keys.changes.removeListener(_recompute);
    _shutDown();
    byProfile.dispose();
    stopped.dispose();
  }

  void _shutDown() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _reauth?.cancel();
    _reauth = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
    _connecting = false;
  }

  void _ensureConnected() {
    if (!_wanted ||
        _socket != null ||
        _connecting ||
        _retry != null ||
        stopped.value != null) {
      return;
    }
    unawaited(_open());
  }

  Future<void> _open() async {
    _connecting = true;
    final generation = _generation;
    try {
      final token = await _token(force: _forceToken);
      _forceToken = false;
      if (generation != _generation) return;
      if (token == null) {
        _connecting = false;
        _scheduleRetry();
        return;
      }
      final socket = await _connect(_url, token.token);
      if (generation != _generation) {
        unawaited(socket.close());
        return;
      }
      _connecting = false;
      _socket = socket;
      _attempt = 0;
      _scheduleReauth(token.expires, generation);
      _subscription = socket.messages.listen(
        (message) => _enqueue(message),
        onDone: () => _closed(socket, generation),
        onError: (Object _) {},
        cancelOnError: false,
      );
    } on PresenceRefused catch (refused) {
      if (generation != _generation) return;
      _connecting = false;
      switch (refused.status) {
        case 402:
          _stop(PresenceStop.notPro);
        case 401:
          _forceToken = true;
          _scheduleRetry();
        default:
          _scheduleRetry();
      }
    } catch (_) {
      if (generation != _generation) return;
      _connecting = false;
      _scheduleRetry();
    }
  }

  void _closed(PresenceSocket socket, int generation) {
    if (generation != _generation || _socket != socket) return;
    _socket = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reauth?.cancel();
    _reauth = null;
    switch (socket.closeCode) {
      case PresenceCloseCode.notPro:
        _stop(PresenceStop.notPro);
      case PresenceCloseCode.revoked:
        _stop(PresenceStop.refused);
      case PresenceCloseCode.badMessage || PresenceCloseCode.noSubprotocol:
        _stop(PresenceStop.protocol);
      case PresenceCloseCode.tokenExpired:
        _forceToken = true;
        _ensureConnected();
      default:
        _scheduleRetry();
    }
  }

  void _stop(PresenceStop reason) {
    _shutDown();
    stopped.value = reason;
  }

  /// Waits 1, 2, 4 ... up to 60 seconds, each picked at random between half
  /// and all of it, so clients dropped together do not all return together.
  void _scheduleRetry() {
    if (!_wanted) return;
    final ceiling = min(60, 1 << min(_attempt, 6));
    _attempt++;
    final millis = (ceiling * 1000 * (0.5 + _random.nextDouble() / 2)).round();
    _retry = Timer(Duration(milliseconds: millis), () {
      _retry = null;
      _ensureConnected();
    });
  }

  void _scheduleReauth(DateTime expires, int generation) {
    _reauth?.cancel();
    var wait = expires.difference(_now()) - const Duration(minutes: 5);
    if (wait < Duration.zero) wait = Duration.zero;
    _reauth = Timer(wait, () => unawaited(_renew(generation)));
  }

  Future<void> _renew(int generation) async {
    final socket = _socket;
    if (generation != _generation || socket == null) return;
    final token = await _token(force: true);
    if (generation != _generation || _socket != socket || token == null) {
      return;
    }
    socket.send(jsonEncode({'type': 'reauth', 'token': token.token}));
    _scheduleReauth(token.expires, generation);
  }

  void _enqueue(String message) {
    _processing = _processing
        .then((_) => _handle(message))
        .catchError((Object _) {});
  }

  Future<void> _handle(String message) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    switch (decoded['type']) {
      case 'snapshot':
        final servers = decoded['servers'];
        if (servers is! List) return;
        _raw.clear();
        for (final server in servers) {
          _store(server);
        }
      case 'server':
        _store(decoded);
      default:
        return;
    }
    await _recomputeNow();
  }

  void _store(Object? server) {
    if (server is! Map) return;
    final id = server['server'];
    final online = server['online'];
    final state = server['state'];
    final at = server['at'];
    if (id is! String || online is! bool || state is! String || at is! int) {
      return;
    }
    _raw[id] = (online: online, state: state, at: at);
  }

  void _recompute() => unawaited(_recomputeNow());

  Future<void> _recomputeNow() async {
    final result = <String, ServerPresence>{};
    final sessions = <String, List<PresenceSession>>{};
    for (final entry in _raw.entries) {
      final keyId = entry.key;
      final profileId = _profileForKey[keyId];
      if (profileId == null) continue;
      final raw = entry.value;
      final key = await _keys.keyFor(profileId);
      final opened = key == null ? null : _openState(key, keyId, raw.state);
      final previous = result[profileId];
      final at = DateTime.fromMillisecondsSinceEpoch(raw.at);
      if (previous != null && previous.at.isAfter(at)) continue;
      result[profileId] = ServerPresence(
        keyId: keyId,
        online: raw.online,
        at: at,
        sessions: opened?.sessions,
      );
      if (opened != null) sessions[profileId] = opened.sessions;
    }
    if (!mapEquals(result, byProfile.value)) byProfile.value = result;
    if (sessions.isNotEmpty) onSessions?.call(sessions);
  }

  OpenedPresence? _openState(Uint8List key, String keyId, String state) {
    final opened = openPresenceState(key, keyId, state);
    if (opened == null) return _opened[keyId];
    if (!_freshness.accept(keyId, opened.writtenAt)) return _opened[keyId];
    return _opened[keyId] = opened;
  }
}

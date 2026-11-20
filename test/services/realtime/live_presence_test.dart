import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/realtime/live_presence.dart';
import 'package:termphin/services/realtime/presence_keys.dart';
import 'package:termphin/services/realtime/presence_socket.dart';
import 'package:termphin/services/realtime/presence_state.dart';
import 'package:termphin/services/security/aead.dart';

import '../../support/fake_master_key_store.dart';

class _FakeSocket implements PresenceSocket {
  final _controller = StreamController<String>.broadcast();
  final sent = <String>[];
  int? code;
  bool closedByClient = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close([int code = 1000]) async {
    closedByClient = true;
    await _controller.close();
  }

  @override
  int? get closeCode => code;

  void push(Object message) => _controller.add(jsonEncode(message));

  void serverClose(int code) {
    this.code = code;
    unawaited(_controller.close());
  }
}

class _Harness {
  _Harness(this.async) {
    presence = LivePresence(
      connect: (url, token) async {
        tokensUsed.add(token);
        final failure = failures.isEmpty ? null : failures.removeAt(0);
        if (failure != null) throw failure;
        final socket = _FakeSocket();
        sockets.add(socket);
        return socket;
      },
      token: ({bool force = false}) async {
        forced.add(force);
        if (tokenMissing > 0) {
          tokenMissing--;
          return null;
        }
        return (token: 'token-${forced.length}', expires: expires);
      },
      keys: keys,
      random: Random(1),
      now: () => DateTime.fromMillisecondsSinceEpoch(0).add(async.elapsed),
    );
  }

  final FakeAsync async;
  late final LivePresence presence;
  final keys = PresenceKeyStore(cipher: cipherFixture());
  final sockets = <_FakeSocket>[];
  final tokensUsed = <String>[];
  final forced = <bool>[];
  final failures = <Object>[];
  int tokenMissing = 0;
  DateTime expires = DateTime.fromMillisecondsSinceEpoch(
    0,
  ).add(const Duration(hours: 1));

  _FakeSocket get socket => sockets.last;
}

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i));

String _state(String keyId, int writtenAt, List<String> names) {
  final plaintext = jsonEncode({
    'v': 1,
    't': writtenAt,
    'sessions': [
      for (final name in names) {'name': name, 'created': 1, 'clients': 0},
    ],
  });
  return sealBytes(
    _key(),
    utf8Bytes(plaintext),
    aad: presenceAad(keyId),
  ).substring(sealPrefix.length);
}

Map<String, Object> _server(String id, bool online, String state, int at) => {
  'server': id,
  'online': online,
  'state': state,
  'at': at,
};

void _withHarness(void Function(FakeAsync async, _Harness h) body) {
  fakeAsync((async) {
    final h = _Harness(async);
    body(async, h);
    h.presence.setWanted(false);
    async.flushMicrotasks();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('apps connect to /v1/app over wss by default', () {
    expect(presenceAppUrl().toString(), 'wss://rt.termphin.dev/v1/app');
    expect(
      presenceAppUrl('http://127.0.0.1:8090').toString(),
      'ws://127.0.0.1:8090/v1/app',
    );
  });

  test('the default URL reaches the server over TLS', () {
    expect(presenceHttpUrl(presenceAppUrl()).scheme, 'https');
  });

  test('a snapshot shows mapped servers with the sessions it can open', () {
    _withHarness((async, h) {
      final shown = <Map<String, List<PresenceSession>>>[];
      h.presence.onSessions = shown.add;
      unawaited(h.keys.remember('profile-a', _key()));
      h.presence.profileForKey = {'key-a': 'profile-a', 'key-b': 'profile-b'};
      h.presence.setWanted(true);
      async.flushMicrotasks();
      expect(h.tokensUsed, ['token-1']);

      h.socket.push({
        'type': 'snapshot',
        'servers': [
          _server('key-a', true, _state('key-a', 5, ['main', 'logs']), 10),
          _server('key-b', true, _state('key-b', 5, ['x']), 10),
          _server('key-unknown', true, '', 10),
        ],
        'devices': <Object>[],
      });
      async.flushMicrotasks();

      final byProfile = h.presence.byProfile.value;
      expect(byProfile.keys, unorderedEquals(['profile-a', 'profile-b']));
      expect(byProfile['profile-a']!.online, isTrue);
      expect(byProfile['profile-a']!.sessions!.map((s) => s.name), [
        'main',
        'logs',
      ]);
      expect(byProfile['profile-b']!.sessions, isNull);
      expect(shown.last.keys, ['profile-a']);
    });
  });

  test('a server event updates one server, an old state is ignored', () {
    _withHarness((async, h) {
      unawaited(h.keys.remember('profile-a', _key()));
      h.presence.profileForKey = {'key-a': 'profile-a'};
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.push({
        'type': 'snapshot',
        'servers': [
          _server('key-a', true, _state('key-a', 5, ['new']), 10),
        ],
        'devices': <Object>[],
      });
      async.flushMicrotasks();
      h.socket.push({
        'type': 'server',
        ..._server('key-a', true, _state('key-a', 4, ['replayed']), 11),
      });
      async.flushMicrotasks();
      expect(
        h.presence.byProfile.value['profile-a']!.sessions!.single.name,
        'new',
      );
      h.socket.push({
        'type': 'server',
        ..._server('key-a', false, _state('key-a', 6, []), 12),
      });
      async.flushMicrotasks();
      final server = h.presence.byProfile.value['profile-a']!;
      expect(server.online, isFalse);
      expect(server.sessions, isEmpty);
    });
  });

  test('a key arriving later opens what was already received', () {
    _withHarness((async, h) {
      h.presence.profileForKey = {'key-a': 'profile-a'};
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.push({
        'type': 'snapshot',
        'servers': [
          _server('key-a', true, _state('key-a', 5, ['main']), 10),
        ],
        'devices': <Object>[],
      });
      async.flushMicrotasks();
      expect(h.presence.byProfile.value['profile-a']!.sessions, isNull);
      unawaited(h.keys.remember('profile-a', _key()));
      async.flushMicrotasks();
      expect(
        h.presence.byProfile.value['profile-a']!.sessions!.single.name,
        'main',
      );
    });
  });

  test('no Pro stops for good, until wanted again', () {
    _withHarness((async, h) {
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.serverClose(PresenceCloseCode.notPro);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(h.sockets, hasLength(1));
      expect(h.presence.stopped.value, PresenceStop.notPro);

      h.presence.setWanted(false);
      h.presence.setWanted(true);
      async.flushMicrotasks();
      expect(h.sockets, hasLength(2));
      expect(h.presence.stopped.value, isNull);
    });
  });

  test('402 before the upgrade stops too', () {
    _withHarness((async, h) {
      h.failures.add(const PresenceRefused(402));
      h.presence.setWanted(true);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(h.sockets, isEmpty);
      expect(h.presence.stopped.value, PresenceStop.notPro);
    });
  });

  test('a revoked account and a protocol error stop', () {
    _withHarness((async, h) {
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.serverClose(PresenceCloseCode.revoked);
      async.flushMicrotasks();
      expect(h.presence.stopped.value, PresenceStop.refused);
    });
    _withHarness((async, h) {
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.serverClose(PresenceCloseCode.badMessage);
      async.flushMicrotasks();
      expect(h.presence.stopped.value, PresenceStop.protocol);
    });
  });

  test('a restart comes back after a jittered, growing backoff', () {
    _withHarness((async, h) {
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.serverClose(1012);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 400));
      expect(h.sockets, hasLength(1));
      async.elapse(const Duration(milliseconds: 700));
      expect(h.sockets, hasLength(2));

      h.failures.addAll([StateError('down'), StateError('down')]);
      h.socket.serverClose(1001);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(h.sockets, hasLength(3));
      expect(h.presence.connected, isTrue);
    });
  });

  test('an expired token reconnects at once with a fresh one', () {
    _withHarness((async, h) {
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.serverClose(PresenceCloseCode.tokenExpired);
      async.flushMicrotasks();
      expect(h.sockets, hasLength(2));
      expect(h.forced, [false, true]);
    });
  });

  test('no token yet is tried again after the backoff', () {
    _withHarness((async, h) {
      h.tokenMissing = 1;
      h.presence.setWanted(true);
      async.flushMicrotasks();
      expect(h.sockets, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(h.sockets, hasLength(1));
    });
  });

  test('401 before the upgrade retries with a fresh token', () {
    _withHarness((async, h) {
      h.failures.add(const PresenceRefused(401));
      h.presence.setWanted(true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(h.sockets, hasLength(1));
      expect(h.forced, [false, true]);
    });
  });

  test('the token is renewed five minutes before it expires', () {
    _withHarness((async, h) {
      h.expires = DateTime.fromMillisecondsSinceEpoch(
        0,
      ).add(const Duration(minutes: 30));
      h.presence.setWanted(true);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 24));
      expect(h.socket.sent, isEmpty);
      h.expires = h.expires.add(const Duration(hours: 1));
      async.elapse(const Duration(minutes: 1, seconds: 1));
      expect(h.socket.sent, hasLength(1));
      final message = jsonDecode(h.socket.sent.single) as Map;
      expect(message, {'type': 'reauth', 'token': 'token-2'});
      expect(h.forced.last, isTrue);
    });
  });

  test('not wanted closes the connection and forgets everything', () {
    _withHarness((async, h) {
      h.presence.profileForKey = {'key-a': 'profile-a'};
      h.presence.setWanted(true);
      async.flushMicrotasks();
      h.socket.push({
        'type': 'snapshot',
        'servers': [_server('key-a', true, '', 10)],
        'devices': <Object>[],
      });
      async.flushMicrotasks();
      expect(h.presence.byProfile.value, isNotEmpty);
      final socket = h.socket;
      h.presence.setWanted(false);
      async.flushMicrotasks();
      expect(socket.closedByClient, isTrue);
      expect(h.presence.byProfile.value, isEmpty);
      async.elapse(const Duration(minutes: 5));
      expect(h.sockets, hasLength(1));
    });
  });
}

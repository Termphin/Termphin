import 'dart:convert';
import 'dart:typed_data';

import '../security/aead.dart';
import 'presence_device.dart';

/// What a session is doing, as its agent last saw it.
enum SessionActivityState {
  /// The shell has the terminal: nothing is running.
  idle,

  /// A program has the terminal and wrote something in the last seconds.
  working,

  /// A program worked for a while, went still and waits for keys or asks
  /// something - what the "went quiet" notification announces.
  waiting,

  /// A program has the terminal and is none of the above.
  running;

  static SessionActivityState? fromName(Object? name) {
    for (final state in values) {
      if (state.name == name) return state;
    }
    return null;
  }
}

/// A session's activity: its state and the program in front, named the way
/// notifications name it - never what follows its first option.
class SessionActivity {
  const SessionActivity({required this.state, this.command});

  final SessionActivityState state;
  final String? command;
}

/// One session an agent reported, as it appears in the sealed state.
class PresenceSession {
  const PresenceSession({
    required this.name,
    required this.createdAt,
    required this.clients,
    this.devices = const [],
    this.activity,
    this.restorable = false,
  });

  final String name;
  final DateTime createdAt;

  /// How many clients were attached when the agent reported.
  final int clients;

  /// The attached clients that said which device they are.
  final List<PresenceDevice> devices;

  /// What the session is doing; null from an agent that does not say.
  final SessionActivity? activity;

  /// Its process is gone - stopped by a reboot - but the agent kept its
  /// screen and working directory, which opening it restores.
  final bool restorable;
}

/// One server as the presence backend describes it, after this device opened
/// its state: whether an agent is reporting for it, and the sessions it
/// holds. [sessions] is null when this device cannot open the state - it has
/// no key for the server yet - or the agent never sent one.
class ServerPresence {
  const ServerPresence({
    required this.keyId,
    required this.online,
    required this.at,
    this.sessions,
  });

  /// The relay key id the backend names the server by.
  final String keyId;
  final bool online;
  final DateTime at;
  final List<PresenceSession>? sessions;
}

/// What a sealed state is bound to, so the backend cannot pass one server's
/// state off as another's. The agent seals with the same string.
String presenceAad(String keyId) => 'termphin-presence:v1:$keyId';

/// An opened state: when the agent wrote it, and the sessions in it.
typedef OpenedPresence = ({int writtenAt, List<PresenceSession> sessions});

/// Opens [state] - the base64 the agent sealed with [key] for the server
/// [keyId] - or returns null when it does not open or does not parse. An
/// empty state means the agent never sent one.
OpenedPresence? openPresenceState(Uint8List key, String keyId, String state) {
  if (state.isEmpty) return null;
  final plain = openBytes(key, '$sealPrefix$state', aad: presenceAad(keyId));
  if (plain == null) return null;
  try {
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map || decoded['v'] != 1) return null;
    final writtenAt = decoded['t'];
    final entries = decoded['sessions'];
    if (writtenAt is! int || entries is! List) return null;
    final sessions = <PresenceSession>[];
    for (final entry in entries) {
      if (entry is! Map) return null;
      final name = entry['name'];
      final created = entry['created'];
      final clients = entry['clients'];
      if (name is! String || created is! int || clients is! int) return null;
      final devices = entry['devices'];
      final activity = entry['activity'];
      final activityState = activity is Map
          ? SessionActivityState.fromName(activity['state'])
          : null;
      final command = activity is Map ? activity['command'] : null;
      sessions.add(
        PresenceSession(
          name: name,
          createdAt: DateTime.fromMillisecondsSinceEpoch(created * 1000),
          clients: clients,
          devices: [
            if (devices is List)
              for (final device in devices)
                if (device is String) ?PresenceDevice.parse(device),
          ],
          restorable: entry['restorable'] == true,
          activity: activityState == null
              ? null
              : SessionActivity(
                  state: activityState,
                  command: command is String && command.isNotEmpty
                      ? command
                      : null,
                ),
        ),
      );
    }
    return (writtenAt: writtenAt, sessions: sessions);
  } catch (_) {
    return null;
  }
}

/// Remembers the newest state accepted per server and refuses an older one,
/// so a backend replaying an old state cannot bring back sessions that have
/// ended. The newest itself is accepted again: it is what every snapshot
/// after a reconnect carries.
class PresenceFreshness {
  final _newest = <String, int>{};

  /// Whether [writtenAt] for [keyId] is at least as new as the last accepted
  /// one; records it when it is.
  bool accept(String keyId, int writtenAt) {
    final newest = _newest[keyId];
    if (newest != null && writtenAt < newest) return false;
    _newest[keyId] = writtenAt;
    return true;
  }

  void clear() => _newest.clear();
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ssh_profile.dart';
import '../services/pro/pro_service.dart';
import '../services/push/machine_switches.dart';
import '../services/push/push_service.dart';
import '../services/realtime/live_presence.dart';
import '../services/realtime/presence_keys.dart';
import '../services/realtime/presence_socket.dart';
import '../services/realtime/presence_state.dart';
import '../services/realtime/presence_token.dart';
import '../services/ssh/network_monitor.dart';
import '../utils/platform_info.dart';
import 'account_provider.dart';
import 'profiles_provider.dart';
import 'ssh_session_manager_provider.dart';

/// Live presence for the app: one [LivePresence] wanted while an account
/// with Pro is signed in and - on a phone - the app is in front, fed with
/// which relay key belongs to which machine, and showing the sessions it
/// reads as session rows.
///
/// Read once by the app gate at launch, which keeps it alive for the
/// process and tells it when the app goes to the background and back.
final livePresenceControllerProvider = Provider<LivePresenceController>((ref) {
  final manager = ref.read(sshSessionManagerProvider);
  final controller = LivePresenceController(
    presence: LivePresence(
      connect: connectPresenceSocket,
      token: firebasePresenceToken,
      keys: presenceKeys,
    ),
    profiles: () => ref.read(profilesProvider),
    isShown: (profileId, name) => manager.tabs.any(
      (session) => session.profile.id == profileId && session.muxName == name,
    ),
    adopt: (profile, name) => manager.adoptRemoteSession(profile, name),
    prune: manager.pruneReportedSessions,
  );
  StreamSubscription<List<RelayServer>>? relayKeys;
  var latestServers = const <RelayServer>[];
  void syncKeys() => controller.presence.profileForKey = liveProfileKeys(
    latestServers,
    pending: PushService.instance.pendingMachines.value,
  );
  PushService.instance.pendingMachines.addListener(syncKeys);
  ref.listen(profilesProvider, (_, _) => controller.syncProfiles());
  ref.listen(accountProvider, (previous, user) {
    if (previous?.uid != user?.uid) {
      unawaited(relayKeys?.cancel());
      relayKeys = null;
      latestServers = const [];
      controller.presence.profileForKey = const {};
      if (user != null) {
        relayKeys = PushService.instance.servers().listen((servers) {
          latestServers = servers;
          syncKeys();
        }, onError: (Object _) {});
      }
    }
    controller.signedIn = user != null;
  }, fireImmediately: true);
  void pro() => controller.pro = ProService.instance.confirmed.value;
  ProService.instance.confirmed.addListener(pro);
  pro();
  final regained = NetworkMonitor.instance.onRegained.listen(
    (_) => controller.presence.retryNow(),
  );
  ref.onDispose(() {
    PushService.instance.pendingMachines.removeListener(syncKeys);
    ProService.instance.confirmed.removeListener(pro);
    unawaited(regained.cancel());
    unawaited(relayKeys?.cancel());
    controller.dispose();
  });
  return controller;
});

/// Relay key ids mapped to their profile id, only for machines whose live
/// status is on (taking local [pending] switches into account before the
/// server hears).
Map<String, String> liveProfileKeys(
  Iterable<RelayServer> servers, {
  Map<String, MachineSwitchChange> pending = const {},
}) {
  final list = servers.toList();
  return {
    for (final server in list)
      if (server.profileId != null &&
          showsLive(server.profileId!, pending: pending, keys: list))
        server.keyId: server.profileId!,
  };
}

/// This install's id, which its own agent reports carry, so a session row
/// can leave this device out of who is attached.
final thisDeviceIdProvider = FutureProvider<String>(
  (ref) => PushService.instance.installId(),
);

/// What the presence backend says about each machine, by profile id.
final livePresenceProvider =
    NotifierProvider<LivePresenceNotifier, Map<String, ServerPresence>>(
      LivePresenceNotifier.new,
    );

/// Republishes [LivePresence.byProfile].
class LivePresenceNotifier extends Notifier<Map<String, ServerPresence>> {
  @override
  Map<String, ServerPresence> build() {
    final source = ref.watch(livePresenceControllerProvider).presence.byProfile;
    final local = ref.watch(sshSessionManagerProvider).localPresence;
    Map<String, ServerPresence> merged() {
      final sessions = local.value;
      if (sessions == null) return source.value;
      return {
        ...source.value,
        kLocalProfileId: ServerPresence(
          keyId: kLocalProfileId,
          online: true,
          at: DateTime.now(),
          sessions: sessions,
        ),
      };
    }

    void update() => state = merged();
    source.addListener(update);
    local.addListener(update);
    ref.onDispose(() {
      source.removeListener(update);
      local.removeListener(update);
    });
    return merged();
  }
}

/// Decides when [presence] runs and turns the sessions it reads into
/// session rows: a row for each session that appeared since the last report
/// and is not on screen already, and no row for a session the report no
/// longer lists. A session seen before is left alone, so a row the user
/// closed does not come back on the next report.
class LivePresenceController {
  LivePresenceController({
    required this.presence,
    required List<SshProfile> Function() profiles,
    required bool Function(String profileId, String name) isShown,
    required void Function(SshProfile profile, String name) adopt,
    required void Function(String profileId, Set<String> alive) prune,
  }) : _profiles = profiles,
       _isShown = isShown,
       _adopt = adopt,
       _prune = prune {
    presence.onSessions = _show;
  }

  final LivePresence presence;
  final List<SshProfile> Function() _profiles;
  final bool Function(String profileId, String name) _isShown;
  final void Function(SshProfile profile, String name) _adopt;
  final void Function(String profileId, Set<String> alive) _prune;
  final _seen = <String, Set<String>>{};
  Map<String, List<PresenceSession>> _lastSessions = const {};

  bool _signedIn = false;
  bool _pro = false;
  bool _foreground = true;

  set signedIn(bool value) {
    _signedIn = value;
    if (!value) {
      _seen.clear();
      _lastSessions = const {};
    }
    _update();
  }

  set pro(bool value) {
    _pro = value;
    _update();
  }

  /// The app went to the background or came back. A phone lets go of the
  /// connection in the background, where the system would cut it anyway; a
  /// desktop keeps it.
  void setForeground(bool value) {
    _foreground = value;
    _update();
  }

  void _update() => presence.setWanted(
    _signedIn && _pro && (_foreground || isDesktopPlatform),
  );

  /// Re-evaluates the latest reported sessions after the saved machine list
  /// changed, such as when sync saves a presence key before profiles reload.
  void syncProfiles() => _apply(_lastSessions);

  void _show(Map<String, List<PresenceSession>> sessionsByProfile) {
    _lastSessions = sessionsByProfile;
    _apply(sessionsByProfile);
  }

  void _apply(Map<String, List<PresenceSession>> sessionsByProfile) {
    final profiles = {for (final profile in _profiles()) profile.id: profile};
    for (final gone
        in _seen.keys
            .where(
              (id) =>
                  !sessionsByProfile.containsKey(id) ||
                  !profiles.containsKey(id),
            )
            .toList()) {
      _seen.remove(gone);
    }
    for (final MapEntry(key: profileId, value: sessions)
        in sessionsByProfile.entries) {
      final profile = profiles[profileId];
      if (profile == null) continue;
      final names = {for (final session in sessions) session.name};
      final seen = _seen[profileId] ?? const {};
      _seen[profileId] = names;
      for (final name in names.difference(seen)) {
        if (!_isShown(profileId, name)) _adopt(profile, name);
      }
      _prune(profileId, names);
    }
  }

  void dispose() => presence.dispose();
}

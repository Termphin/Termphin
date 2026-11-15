import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh/network_monitor.dart';
import '../services/sync/settings_sync.dart';
import '../services/sync/sync_coordinator.dart';
import '../services/sync/sync_service.dart';
import 'account_provider.dart';
import 'groups_provider.dart';
import 'profiles_provider.dart';
import 'snippets_provider.dart';
import 'ssh_keys_provider.dart';

/// Automatic sync for the app: one [SyncCoordinator] that hears every edit to
/// machines, keys, snippets, groups and the synced preferences, reloads
/// them after a pull, and starts and stops with the account.
///
/// Read once by the app gate at launch, which keeps it alive for the
/// process; the gate also tells it when the app comes back to the
/// foreground.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    service: SyncService.instance,
    reload: () async {
      await ref.read(profilesProvider.notifier).loadProfiles();
      await ref.read(profileGroupsProvider.notifier).loadGroups();
      await ref.read(snippetsProvider.notifier).loadSnippets();
      ref.read(sshKeysRevisionProvider.notifier).bump();
    },
  );
  void changed(Object? _, Object? _) => coordinator.localChanged();
  ref.listen(profilesProvider, changed);
  ref.listen(profileGroupsProvider, changed);
  ref.listen(snippetsProvider, changed);
  ref.listen(sshKeysRevisionProvider, changed);
  final regained = NetworkMonitor.instance.onRegained.listen(
    (_) => coordinator.networkRegained(),
  );
  ref.onDispose(regained.cancel);
  final settings = Listenable.merge(SettingsSync.listenables);
  settings.addListener(coordinator.localChanged);
  ref.onDispose(() => settings.removeListener(coordinator.localChanged));
  ref.listen(accountProvider, (previous, next) {
    if (next == null) {
      coordinator.stop();
    } else if (previous?.uid != next.uid) {
      unawaited(coordinator.start());
    }
  }, fireImmediately: true);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

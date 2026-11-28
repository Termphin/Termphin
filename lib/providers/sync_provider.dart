import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/pro/pro_service.dart';
import '../services/ssh/network_monitor.dart';
import '../services/sync/storage_sync_local.dart';
import '../services/sync/sync_coordinator.dart';
import '../services/sync/sync_service.dart';
import 'account_provider.dart';
import 'groups_provider.dart';
import 'profiles_provider.dart';
import 'snippets_provider.dart';
import 'ssh_keys_provider.dart';
import 'stored_data_reload.dart';

/// Automatic sync for the app: one [SyncCoordinator] that hears every edit to
/// machines, keys, snippets, groups, presence keys and the synced
/// preferences, reloads them after a pull, starts and stops with the
/// account, and starts again when the account's Pro is confirmed.
///
/// Read once by the app gate at launch, which keeps it alive for the
/// process; the gate also tells it when the app comes back to the
/// foreground.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    service: SyncService.instance,
    reload: () => reloadStoredData(ref.read),
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
  final local = syncedLocalChanges();
  local.addListener(coordinator.localChanged);
  ref.onDispose(() => local.removeListener(coordinator.localChanged));
  void pro() {
    if (ProService.instance.confirmed.value) coordinator.proConfirmed();
  }

  ProService.instance.confirmed.addListener(pro);
  ref.onDispose(() => ProService.instance.confirmed.removeListener(pro));
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

/// Whether automatic sync runs on this device: republishes
/// [SyncCoordinator.running].
final syncRunningProvider = NotifierProvider<SyncRunningNotifier, bool>(
  SyncRunningNotifier.new,
);

/// Republishes [SyncCoordinator.running].
class SyncRunningNotifier extends Notifier<bool> {
  @override
  bool build() {
    final running = ref.watch(syncCoordinatorProvider).running;
    void update() => state = running.value;
    running.addListener(update);
    ref.onDispose(() => running.removeListener(update));
    return running.value;
  }
}

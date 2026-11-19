import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/sync/sync_coordinator.dart';
import 'package:termphin/services/sync/sync_crypto.dart';
import 'package:termphin/services/sync/sync_engine.dart';
import 'package:termphin/services/sync/sync_service.dart';

import '../../support/sync_fakes.dart';

void main() {
  late FakeSyncCloud cloud;
  late FakeSyncVault vault;
  late SyncService service;
  late SyncCoordinator coordinator;
  late int reloads;

  const delay = Duration(milliseconds: 60);

  Future<void> wait(Duration duration) => Future<void>.delayed(duration);

  SyncService device(FakeSyncVault vault, FakeSyncLocal local) =>
      SyncService(cloud: cloud, vault: vault, local: local, uid: () => 'u1');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = FakeSyncCloud();
    vault = FakeSyncVault();
    reloads = 0;
    service = device(vault, FakeSyncLocal());
    coordinator = SyncCoordinator(
      service: service,
      reload: () async {
        reloads++;
        coordinator.localChanged();
      },
      localDelay: delay,
      remoteDelay: delay,
      resumeGap: const Duration(hours: 1),
    );
  });

  tearDown(() => coordinator.dispose());

  void giveKey() {
    vault.keys['u1'] = Uint8List(32);
    cloud.meta ??= SyncMeta(
      salt: Uint8List(16),
      iterations: kSyncKdfIterations,
      check: SyncKey(Uint8List(32)).sealCheck('u1'),
    );
  }

  test(
    'a run that failed offline is tried again once the network is back',
    () async {
      giveKey();
      cloud.refusal = const SyncException(SyncFailure.network);
      await coordinator.start();
      expect(coordinator.activity.value, SyncActivity.failed);

      cloud.refusal = null;
      coordinator.networkRegained();
      await wait(delay);

      expect(coordinator.activity.value, SyncActivity.idle);
      expect(service.lastSynced.value, isNotNull);
    },
  );

  test('the network coming back after a good run starts nothing', () async {
    giveKey();
    await coordinator.start();
    final synced = service.lastSynced.value;

    coordinator.networkRegained();
    await wait(delay);

    expect(service.lastSynced.value, synced);
  });

  test('a device without the key neither syncs nor listens', () async {
    await coordinator.start();
    coordinator.localChanged();
    await wait(delay * 2);

    expect(coordinator.active, isFalse);
    expect(cloud.fetches, 0);
  });

  test('a device with the key syncs as soon as it starts', () async {
    giveKey();
    await coordinator.start();

    expect(coordinator.active, isTrue);
    expect(cloud.fetches, 1);
    expect(coordinator.activity.value, SyncActivity.idle);
    expect(coordinator.lastSynced.value, isNotNull);
  });

  test('edits close together sync once, after the last of them', () async {
    giveKey();
    await coordinator.start();

    coordinator.localChanged();
    await wait(delay ~/ 2);
    coordinator.localChanged();
    await wait(delay ~/ 2);
    coordinator.localChanged();
    expect(cloud.fetches, 1);

    await wait(delay * 2);
    expect(cloud.fetches, 2);
  });

  test('another device writing is pulled in and reloaded, and the reload '
      'is not taken for an edit here', () async {
    giveKey();
    await coordinator.start();

    final other = device(
      FakeSyncVault()..keys['u1'] = Uint8List(32),
      FakeSyncLocal([
        SyncRecord(
          kind: 'snippet',
          id: 's1',
          data: const {'name': 'uptime'},
          updatedAt: DateTime(2026),
        ),
      ]),
    );
    await other.syncNow();
    SharedPreferences.setMockInitialValues({});
    final before = cloud.fetches;
    cloud.remoteChanges.add(null);
    await wait(delay * 2);

    expect(cloud.fetches, before + 1);
    expect(reloads, 1);
    await wait(delay * 2);
    expect(cloud.fetches, before + 1);
  });

  test(
    'a machine another device deleted leaves this one\'s list too',
    () async {
      giveKey();
      final snippet = SyncRecord(
        kind: 'snippet',
        id: 's1',
        data: const {'name': 'uptime'},
        updatedAt: DateTime(2026),
      );
      final here = FakeSyncLocal([snippet]);
      final mine = SyncCoordinator(
        service: device(vault, here),
        reload: () async => reloads++,
        localDelay: delay,
        remoteDelay: delay,
        resumeGap: const Duration(hours: 1),
      );
      addTearDown(mine.dispose);
      await mine.start();
      await wait(delay * 2);
      final agreedHere = {
        for (final key in (await SharedPreferences.getInstance()).getKeys())
          key: (await SharedPreferences.getInstance()).get(key)!,
      };

      final other = device(
        FakeSyncVault()..keys['u1'] = Uint8List(32),
        FakeSyncLocal(),
      );
      await other.syncNow();
      SharedPreferences.setMockInitialValues(agreedHere);
      final before = reloads;
      cloud.remoteChanges.add(null);
      await wait(delay * 2);

      expect(here.records, isEmpty);
      expect(reloads, before + 1);
    },
  );

  test('a sync asked for during another runs once more after it', () async {
    giveKey();
    await coordinator.start();

    final first = coordinator.syncNow();
    final second = coordinator.syncNow();
    final third = coordinator.syncNow();
    await Future.wait([first, second, third]);

    expect(cloud.fetches, 3);
  });

  test('losing Pro stops it quietly', () async {
    giveKey();
    await coordinator.start();

    cloud.refusal = const SyncException(SyncFailure.notPro);
    await coordinator.syncNow();

    expect(coordinator.active, isFalse);
    expect(coordinator.activity.value, SyncActivity.paused);
    coordinator.localChanged();
    await wait(delay * 2);
    expect(cloud.fetches, 1);
  });

  test('a failed sync is reported and tried again on the next edit', () async {
    giveKey();
    await coordinator.start();

    cloud.refusal = const SyncException(SyncFailure.network);
    await coordinator.syncNow();
    expect(coordinator.activity.value, SyncActivity.failed);
    expect(coordinator.active, isTrue);

    cloud.refusal = null;
    coordinator.localChanged();
    await wait(delay * 2);
    expect(coordinator.activity.value, SyncActivity.idle);
  });

  test(
    'sync turned off from another device stops this one and says so',
    () async {
      giveKey();
      await coordinator.start();

      await cloud.deleteAll('u1');
      await coordinator.syncNow();

      expect(coordinator.active, isFalse);
      expect(coordinator.ended.value, SyncFailure.turnedOff);
      expect(vault.keys, isEmpty);
    },
  );

  test(
    'a new passphrase set elsewhere stops this one until it is given',
    () async {
      giveKey();
      await coordinator.start();

      cloud.meta = SyncMeta(
        salt: Uint8List(16),
        iterations: kSyncKdfIterations,
        check: SyncKey(Uint8List(32)..[0] = 1).sealCheck('u1'),
      );
      await coordinator.syncNow();

      expect(coordinator.ended.value, SyncFailure.passphraseChanged);
      expect(vault.keys, isEmpty);
    },
  );

  test('losing Pro pauses rather than ends', () async {
    giveKey();
    await coordinator.start();

    cloud.refusal = const SyncException(SyncFailure.notPro);
    await coordinator.syncNow();

    expect(coordinator.activity.value, SyncActivity.paused);
    expect(coordinator.ended.value, isNull);
    expect(vault.keys, isNotEmpty);
  });

  test('coming back soon after a sync does not sync again', () async {
    giveKey();
    await coordinator.start();

    coordinator.resumed();
    await wait(delay);

    expect(cloud.fetches, 1);
  });
}

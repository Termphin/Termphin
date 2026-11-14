import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/sync/sync_engine.dart';
import 'package:termphin/services/sync/sync_service.dart';

class _Cloud implements SyncCloud {
  SyncMeta? meta;
  final docs = <String, RemoteEntry>{};

  @override
  Future<SyncMeta?> readMeta(String uid) async => meta;

  @override
  Future<bool> createMeta(String uid, SyncMeta value) async {
    if (meta != null) return false;
    meta = value;
    return true;
  }

  @override
  SyncRemote records(String uid) => _Records(docs);

  @override
  Stream<void> watch(String uid) => const Stream.empty();

  @override
  Future<void> deleteAll(String uid) async {
    meta = null;
    docs.clear();
  }
}

class _Records implements SyncRemote {
  _Records(this.docs);

  final Map<String, RemoteEntry> docs;

  @override
  Future<Map<String, RemoteEntry>> fetchAll() async => Map.of(docs);

  @override
  Future<void> put(String documentId, RemoteEntry entry) async =>
      docs[documentId] = entry;
}

class _Vault implements SyncKeyVault {
  final keys = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String uid) async => keys[uid];

  @override
  Future<void> write(String uid, Uint8List key) async => keys[uid] = key;

  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

class _Local implements SyncLocal {
  final records = <String, SyncRecord>{};

  @override
  Future<List<SyncRecord>> readAll() async => records.values.toList();

  @override
  Future<void> upsert(SyncRecord record) async => records[record.id] = record;

  @override
  Future<void> delete(String kind, String id) async => records.remove(id);
}

void main() {
  late _Cloud cloud;
  String? uid;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    uid = 'u1';
  });

  SyncService device(_Vault vault, _Local local) =>
      SyncService(cloud: cloud, vault: vault, local: local, uid: () => uid);

  test('nobody signed in: nothing to sync', () async {
    uid = null;

    expect(await device(_Vault(), _Local()).state(), SyncState.signedOut);
  });

  test('set up on one device, unlocked on another, records travel', () async {
    final phoneLocal = _Local()
      ..records['s1'] = SyncRecord(
        kind: 'snippet',
        id: 's1',
        data: const {'name': 'deploy'},
        updatedAt: DateTime.utc(2026),
      );
    final phone = device(_Vault(), phoneLocal);
    final tablet = device(_Vault(), _Local());

    expect(await phone.state(), SyncState.notSetUp);
    final pushed = await phone.setUp('correct horse');
    expect(pushed.pushed, 1);
    expect(await phone.state(), SyncState.ready);

    expect(await tablet.state(), SyncState.locked);
    await tablet.unlock('correct horse');
    expect(await tablet.state(), SyncState.ready);
  });

  test('a wrong passphrase is refused before anything is touched', () async {
    await device(_Vault(), _Local()).setUp('correct horse');
    final local = _Local();
    final tablet = device(_Vault(), local);

    await expectLater(
      tablet.unlock('wrong horse'),
      throwsA(
        isA<SyncException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.wrongPassphrase,
        ),
      ),
    );
    expect(await tablet.state(), SyncState.locked);
    expect(local.records, isEmpty);
  });

  test('setting up an account that already syncs is refused', () async {
    await device(_Vault(), _Local()).setUp('first');

    await expectLater(
      device(_Vault(), _Local()).setUp('second'),
      throwsA(
        isA<SyncException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.alreadySetUp,
        ),
      ),
    );
  });

  test('stopping on this device forgets the key, not the account', () async {
    final vault = _Vault();
    final phone = device(vault, _Local());
    await phone.setUp('correct horse');

    await phone.forgetOnThisDevice();

    expect(vault.keys, isEmpty);
    expect(await phone.state(), SyncState.locked);
    expect(cloud.meta, isNotNull);
  });

  test(
    'stopping on this device forgets when each group last changed',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync_setting_times': '{"terminal.scheme":["abc",1000]}',
      });
      final phone = device(_Vault(), _Local());

      await phone.forgetOnThisDevice();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('sync_setting_times'), isNull);
    },
  );

  test('the cloud holds a salt and a check, never the passphrase', () async {
    await device(_Vault(), _Local()).setUp('correct horse');

    expect(cloud.meta!.salt, hasLength(16));
    expect(cloud.meta!.check, isNot(contains('correct')));
  });
}

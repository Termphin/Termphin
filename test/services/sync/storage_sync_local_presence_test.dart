import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/realtime/presence_keys.dart';
import 'package:termphin/services/sync/storage_sync_local.dart';
import 'package:termphin/services/sync/sync_engine.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/secure_storage_channel.dart';

void main() {
  late PresenceKeyStore presence;
  late StorageSyncLocal local;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    presence = PresenceKeyStore(
      cipher: cipherFixture(store: FakeMasterKeyStore()),
    );
    local = StorageSyncLocal(presence: presence);
  });

  SyncRecord record(Map<String, Object?> data) => SyncRecord(
    kind: SyncKind.presenceKey,
    id: 'profile-1',
    data: data,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  test(
    'a key from the account is kept, sealed like one learned here',
    () async {
      final key = newPresenceKey();
      await local.upsert(record(presenceKeyData(key)));
      expect(await presence.keyFor('profile-1'), key);
    },
  );

  test('a damaged record never replaces a good key', () async {
    final key = newPresenceKey();
    await presence.remember('profile-1', key);
    await local.upsert(record({'key': 'garbage'}));
    await local.upsert(record(const {}));
    expect(await presence.keyFor('profile-1'), key);
  });

  test('a deletion pulled for a key is ignored: older apps delete kinds '
      'they do not know', () async {
    final key = newPresenceKey();
    await presence.remember('profile-1', key);
    await local.delete(SyncKind.presenceKey, 'profile-1');
    expect(await presence.keyFor('profile-1'), key);
  });

  test('a machine deleted by sync takes its key along', () async {
    await presence.remember('profile-1', newPresenceKey());
    await local.delete(SyncKind.profile, 'profile-1');
    expect(await presence.keyFor('profile-1'), isNull);
  });
}

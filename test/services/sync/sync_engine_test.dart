import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/sync/sync_crypto.dart';
import 'package:termphin/services/sync/sync_engine.dart';

class _Remote implements SyncRemote {
  final docs = <String, RemoteEntry>{};

  @override
  Future<Map<String, RemoteEntry>> fetchAll() async => Map.of(docs);

  @override
  Future<void> put(String documentId, RemoteEntry entry) async =>
      docs[documentId] = entry;
}

class _Device implements SyncLocal, SyncBaseStore {
  final records = <String, SyncRecord>{};
  Map<String, String> agreed = {};

  void set(String id, Map<String, Object?> data, DateTime at) =>
      records['snippet/$id'] = SyncRecord(
        kind: 'snippet',
        id: id,
        data: data,
        updatedAt: at,
      );

  Map<String, Object?>? get(String id) => records['snippet/$id']?.data;

  @override
  Future<List<SyncRecord>> readAll() async => records.values.toList();

  @override
  Future<void> upsert(SyncRecord record) async =>
      records['${record.kind}/${record.id}'] = record;

  @override
  Future<void> delete(String kind, String id) async =>
      records.remove('$kind/$id');

  @override
  Future<Map<String, String>> read() async => Map.of(agreed);

  @override
  Future<void> write(Map<String, String> hashes) async => agreed = hashes;
}

void main() {
  final key = SyncKey(Uint8List.fromList(List.generate(32, (i) => i)));
  final other = SyncKey(Uint8List.fromList(List.generate(32, (i) => 31 - i)));
  final t0 = DateTime.utc(2026, 11, 13, 20);
  late _Remote remote;
  late _Device a;
  late _Device b;

  setUp(() {
    remote = _Remote();
    a = _Device();
    b = _Device();
  });

  Future<SyncReport> sync(
    _Device device, {
    SyncKey? withKey,
    String uid = 'u1',
  }) => SyncEngine(
    key: withKey ?? key,
    uid: uid,
    remote: remote,
    local: device,
    base: device,
  ).run();

  test('a record made on one device reaches the other', () async {
    a.set('s1', {'name': 'deploy'}, t0);

    await sync(a);
    await sync(b);

    expect(b.get('s1'), {'name': 'deploy'});
  });

  test('the store holds nothing it can read without the key', () async {
    a.set('s1', {'name': 'deploy', 'command': 'make release'}, t0);

    await sync(a);

    final stored = remote.docs.entries.single;
    expect(stored.key, isNot(contains('s1')));
    expect(stored.value.ciphertext, isNot(contains('deploy')));
    expect(stored.value.ciphertext, isNot(contains('snippet')));
  });

  test('a change on one side wins over an unchanged other', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a);
    await sync(b);

    b.set('s1', {'name': 'v2'}, t0.add(const Duration(minutes: 1)));
    await sync(b);
    await sync(a);

    expect(a.get('s1'), {'name': 'v2'});
  });

  test(
    'a change made with an older clock still wins when it is the only one',
    () async {
      a.set('s1', {'name': 'v1'}, t0);
      await sync(a);
      await sync(b);

      b.set('s1', {'name': 'v2'}, t0.subtract(const Duration(days: 1)));
      await sync(b);
      await sync(a);

      expect(a.get('s1'), {'name': 'v2'});
    },
  );

  test('both sides changed: the later change wins on both', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a);
    await sync(b);

    a.set('s1', {'name': 'from a'}, t0.add(const Duration(minutes: 1)));
    b.set('s1', {'name': 'from b'}, t0.add(const Duration(minutes: 2)));
    await sync(a);
    await sync(b);
    await sync(a);

    expect(a.get('s1'), {'name': 'from b'});
    expect(b.get('s1'), {'name': 'from b'});
  });

  test('a deletion reaches the other device', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a);
    await sync(b);

    a.records.clear();
    final report = await sync(a);
    await sync(b);

    expect(report.deletedThere, 1);
    expect(b.get('s1'), isNull);
  });

  test('a record changed after the other side deleted it comes back', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a);
    await sync(b);

    a.records.clear();
    await sync(a);
    b.set('s1', {'name': 'kept'}, t0.add(const Duration(minutes: 5)));
    await sync(b);
    await sync(a);

    expect(a.get('s1'), {'name': 'kept'});
  });

  test(
    'a deletion seen by a device that never had the record does nothing',
    () async {
      a.set('s1', {'name': 'v1'}, t0);
      await sync(a);
      a.records.clear();
      await sync(a);

      await sync(b);

      expect(b.records, isEmpty);
    },
  );

  test('a second sync with nothing changed moves nothing', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a);

    final report = await sync(a);

    expect(report.pushed, 0);
    expect(report.pulled, 0);
  });

  test('records sealed with another passphrase are left alone', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a);

    final report = await sync(b, withKey: other);

    expect(report.unreadable, 1);
    expect(b.records, isEmpty);
    expect(remote.docs, hasLength(1));
  });

  test('a record cannot be read as another account\'s', () async {
    a.set('s1', {'name': 'v1'}, t0);
    await sync(a, uid: 'u1');

    final report = await sync(b, uid: 'u2');

    expect(report.unreadable, 1);
  });

  test('the passphrase check tells a right key from a wrong one', () {
    final check = key.sealCheck('u1');

    expect(key.opensCheck('u1', check), isTrue);
    expect(other.opensCheck('u1', check), isFalse);
    expect(key.opensCheck('u2', check), isFalse);
  });

  test('a content hash ignores key order', () {
    expect(
      contentHash({
        'a': 1,
        'b': [1, 2],
      }),
      contentHash({
        'b': [1, 2],
        'a': 1,
      }),
    );
    expect(contentHash({'a': 1}), isNot(contentHash({'a': 2})));
  });
}

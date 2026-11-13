import 'dart:typed_data';

import 'package:termphin/services/sync/sync_engine.dart';
import 'package:termphin/services/sync/sync_service.dart';

/// An account's sync settings and records, in memory.
class FakeSyncCloud implements SyncCloud {
  SyncMeta? meta;
  final docs = <String, RemoteEntry>{};

  @override
  Future<SyncMeta?> readMeta(String uid) async => meta;

  @override
  Future<bool> createMeta(String uid, SyncMeta value) async {
    meta ??= value;
    return identical(meta, value);
  }

  @override
  SyncRemote records(String uid) => FakeSyncRecords(docs);
}

/// Records of [FakeSyncCloud].
class FakeSyncRecords implements SyncRemote {
  FakeSyncRecords(this.docs);

  final Map<String, RemoteEntry> docs;

  @override
  Future<Map<String, RemoteEntry>> fetchAll() async => Map.of(docs);

  @override
  Future<void> put(String documentId, RemoteEntry entry) async =>
      docs[documentId] = entry;
}

/// A keystore that forgets with the process.
class FakeSyncVault implements SyncKeyVault {
  final keys = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String uid) async => keys[uid];

  @override
  Future<void> write(String uid, Uint8List key) async => keys[uid] = key;

  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

/// A device with nothing on it.
class FakeSyncLocal implements SyncLocal {
  @override
  Future<List<SyncRecord>> readAll() async => const [];

  @override
  Future<void> upsert(SyncRecord record) async {}

  @override
  Future<void> delete(String kind, String id) async {}
}

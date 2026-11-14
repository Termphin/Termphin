import 'dart:async';
import 'dart:typed_data';

import 'package:termphin/services/sync/sync_engine.dart';
import 'package:termphin/services/sync/sync_service.dart';

/// An account's sync settings and records, in memory.
class FakeSyncCloud implements SyncCloud {
  SyncMeta? meta;
  final docs = <String, RemoteEntry>{};

  /// Thrown by [readMeta] when set, as the cloud refusing the account.
  Object? refusal;

  @override
  Future<SyncMeta?> readMeta(String uid) async {
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return meta;
  }

  @override
  Future<bool> createMeta(String uid, SyncMeta value) async {
    meta ??= value;
    return identical(meta, value);
  }

  /// How many syncs have reached the records.
  int fetches = 0;

  @override
  SyncRemote records(String uid) {
    fetches++;
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return FakeSyncRecords(docs);
  }

  /// Add to it to play another device changing the records.
  // ignore: close_sinks
  final remoteChanges = StreamController<void>.broadcast();

  @override
  Stream<void> watch(String uid) => remoteChanges.stream;

  @override
  Future<void> deleteAll(String uid) async {
    meta = null;
    docs.clear();
  }
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

/// A device's records in memory, empty unless given some.
class FakeSyncLocal implements SyncLocal {
  FakeSyncLocal([Iterable<SyncRecord> records = const []]) {
    for (final record in records) {
      this.records['${record.kind}/${record.id}'] = record;
    }
  }

  final records = <String, SyncRecord>{};

  @override
  Future<List<SyncRecord>> readAll() async => records.values.toList();

  @override
  Future<void> upsert(SyncRecord record) async =>
      records['${record.kind}/${record.id}'] = record;

  @override
  Future<void> delete(String kind, String id) async =>
      records.remove('$kind/$id');
}

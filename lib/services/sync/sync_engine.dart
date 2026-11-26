import 'package:clock/clock.dart';

import 'sync_crypto.dart';

/// One synced thing, in the clear, as both sides of a sync see it.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.id,
    required this.data,
    required this.updatedAt,
  });

  /// `profile`, `key`, `snippet`, `groups`, `knownHost`, `presenceKey`,
  /// `setting`.
  final String kind;
  final String id;
  final Map<String, Object?> data;

  /// When it last changed, by the clock of the device that changed it. Only
  /// settles a conflict, where both sides changed it since the last sync.
  final DateTime updatedAt;

  String get hash => contentHash(data);
}

/// What the store holds for a record: its sealed payload, or that it was
/// deleted.
class RemoteEntry {
  const RemoteEntry({required this.ciphertext, required this.deleted});

  final String ciphertext;
  final bool deleted;
}

/// The cloud side, as encrypted documents keyed by [SyncKey.documentId].
abstract interface class SyncRemote {
  Future<Map<String, RemoteEntry>> fetchAll();

  Future<void> put(String documentId, RemoteEntry entry);
}

/// This device's side: what it holds, and the ways to change it.
abstract interface class SyncLocal {
  Future<List<SyncRecord>> readAll();

  Future<void> upsert(SyncRecord record);

  Future<void> delete(String kind, String id);
}

/// What the device remembers between syncs: the hash each record had when it
/// last agreed with the store. That is what tells "I changed it" from "the
/// other device changed it" from "both did".
abstract interface class SyncBaseStore {
  Future<Map<String, String>> read();

  Future<void> write(Map<String, String> hashes);
}

/// What a sync did, for the screen to report.
class SyncReport {
  const SyncReport({
    this.pulled = 0,
    this.pushed = 0,
    this.deletedHere = 0,
    this.deletedThere = 0,
    this.unreadable = 0,
  });

  final int pulled;
  final int pushed;
  final int deletedHere;
  final int deletedThere;

  /// Documents this key could not open: sealed with another passphrase, or
  /// damaged. Left alone.
  final int unreadable;
}

/// Two-way sync of [SyncRecord]s, end-to-end encrypted.
///
/// A three-way merge against the last agreed state ([SyncBaseStore]): a
/// record only one side changed takes that side; one both changed takes the
/// newer `updatedAt`, and on a tie the account's copy - a device joining
/// sync, whose untouched settings carry no time, adopts the account's
/// rather than overwriting them with its defaults; one a side deleted is
/// deleted on the other unless the
/// other changed it meanwhile, which brings it back. A deletion is kept in
/// the store as a tombstone so a device that has been away learns of it.
class SyncEngine {
  SyncEngine({
    required this.key,
    required this.uid,
    required this.remote,
    required this.local,
    required this.base,
  });

  final SyncKey key;
  final String uid;
  final SyncRemote remote;
  final SyncLocal local;
  final SyncBaseStore base;

  Future<SyncReport> run() async {
    final remoteEntries = await remote.fetchAll();
    final localRecords = {
      for (final record in await local.readAll())
        key.documentId(record.kind, record.id): record,
    };
    final agreed = await base.read();
    final next = <String, String>{};

    var pulled = 0;
    var pushed = 0;
    var deletedHere = 0;
    var deletedThere = 0;
    var unreadable = 0;

    final remoteRecords = <String, SyncRecord?>{};
    final ownedRemote = <String>{};
    for (final MapEntry(key: documentId, value: entry)
        in remoteEntries.entries) {
      final payload = key.open(
        entry.ciphertext,
        uid: uid,
        documentId: documentId,
      );
      if (payload == null) {
        unreadable++;
        continue;
      }
      ownedRemote.add(documentId);
      remoteRecords[documentId] = entry.deleted ? null : _fromPayload(payload);
    }

    Future<void> push(String documentId, SyncRecord record) async {
      await remote.put(
        documentId,
        RemoteEntry(
          ciphertext: key.seal(
            _toPayload(record),
            uid: uid,
            documentId: documentId,
          ),
          deleted: false,
        ),
      );
      next[documentId] = record.hash;
      pushed++;
    }

    Future<void> tombstone(String documentId, SyncRecord gone) async {
      await remote.put(
        documentId,
        RemoteEntry(
          ciphertext: key.seal(
            {'kind': gone.kind, 'id': gone.id},
            uid: uid,
            documentId: documentId,
          ),
          deleted: true,
        ),
      );
      deletedThere++;
    }

    final ids = {...localRecords.keys, ...ownedRemote, ...agreed.keys};
    for (final documentId in ids) {
      final mine = localRecords[documentId];
      final theirs = remoteRecords[documentId];
      final known = ownedRemote.contains(documentId);
      final last = agreed[documentId];

      if (mine == null && !known) continue;

      if (mine != null && !known) {
        await push(documentId, mine);
        continue;
      }

      if (mine == null) {
        if (theirs == null) continue;
        if (last == null || last != theirs.hash) {
          await local.upsert(theirs);
          next[documentId] = theirs.hash;
          pulled++;
        } else {
          await tombstone(documentId, theirs);
        }
        continue;
      }

      if (theirs == null) {
        if (last != null && last == mine.hash) {
          await local.delete(mine.kind, mine.id);
          deletedHere++;
        } else {
          await push(documentId, mine);
        }
        continue;
      }

      if (mine.hash == theirs.hash) {
        next[documentId] = mine.hash;
        continue;
      }
      final iChanged = last != mine.hash;
      final theyChanged = last != theirs.hash;
      final takeTheirs =
          !iChanged ||
          (theyChanged && !theirs.updatedAt.isBefore(mine.updatedAt));
      if (takeTheirs) {
        await local.upsert(theirs);
        next[documentId] = theirs.hash;
        pulled++;
      } else {
        await push(documentId, mine);
      }
    }

    await base.write(next);
    return SyncReport(
      pulled: pulled,
      pushed: pushed,
      deletedHere: deletedHere,
      deletedThere: deletedThere,
      unreadable: unreadable,
    );
  }

  static Map<String, Object?> _toPayload(SyncRecord record) => {
    'kind': record.kind,
    'id': record.id,
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
    'data': record.data,
  };

  static SyncRecord? _fromPayload(Map<String, Object?> payload) {
    final kind = payload['kind'];
    final id = payload['id'];
    final data = payload['data'];
    if (kind is! String || id is! String || data is! Map) return null;
    return SyncRecord(
      kind: kind,
      id: id,
      data: data.cast<String, Object?>(),
      updatedAt:
          DateTime.tryParse('${payload['updatedAt']}') ?? clock.now().toUtc(),
    );
  }
}

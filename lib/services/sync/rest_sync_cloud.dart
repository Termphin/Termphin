import 'dart:async';
import 'dart:convert';

import '../firebase/firestore_rest.dart';
import 'sync_engine.dart';
import 'sync_service.dart';

export '../firebase/firestore_rest.dart' show FirestoreAnswer, FirestoreSend;

/// `users/{uid}/syncMeta/key` and `users/{uid}/records/*` through
/// Firestore's REST API ([FirestoreRest]), for a computer, where the
/// Firestore plugin does not run. The same documents, the same security
/// rules and the same sealed records as on a phone; only the way there
/// differs.
///
/// Firestore's REST API has no live listener, so [watch] asks every
/// [pollEvery] for the newest record alone - one document read - and fires
/// when it is not what it was, and not what this computer wrote itself.
class RestSyncCloud implements SyncCloud {
  RestSyncCloud({
    FirestoreSend? send,
    Future<String?> Function()? token,
    this.pollEvery = const Duration(minutes: 1),
  }) : _rest = FirestoreRest(send: send, token: token);

  final FirestoreRest _rest;
  final Duration pollEvery;

  /// What this computer last wrote to each record; see [ownWritesOnly].
  final _written = <String, String>{};

  static const _root = FirestoreRest.root;

  static String _name(String path) => FirestoreRest.name(path);

  Future<FirestoreAnswer> _call(String method, Uri url, {Object? body}) async {
    try {
      return await _rest.call(method, url, body: body);
    } on FirestoreRestException catch (error) {
      throw SyncException(switch (error.failure) {
        FirestoreRestFailure.network => SyncFailure.network,
        FirestoreRestFailure.denied => SyncFailure.notPro,
        _ => SyncFailure.unknown,
      });
    }
  }

  @override
  Future<SyncMeta?> readMeta(String uid) async {
    final answer = await _call(
      'GET',
      Uri.parse('$_root/users/$uid/syncMeta/key'),
    );
    if (answer.status == 404) return null;
    _check(answer);
    final fields = FirestoreRest.fields(answer.body);
    final salt = FirestoreRest.string(fields['salt']);
    final iterations = int.tryParse(
      '${FirestoreRest.value(fields['iterations'])}',
    );
    final check = FirestoreRest.string(fields['check']);
    if (salt == null || iterations == null || check == null) return null;
    return SyncMeta(
      salt: base64Decode(salt),
      iterations: iterations,
      check: check,
    );
  }

  @override
  Future<bool> createMeta(String uid, SyncMeta meta) async {
    final answer = await _call(
      'POST',
      Uri.parse('$_root:commit'),
      body: {
        'writes': [
          {
            'update': {
              'name': _name('users/$uid/syncMeta/key'),
              'fields': {
                'salt': {'stringValue': base64Encode(meta.salt)},
                'iterations': {'integerValue': '${meta.iterations}'},
                'check': {'stringValue': meta.check},
              },
            },
            'currentDocument': {'exists': false},
            'updateTransforms': [
              {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
            ],
          },
        ],
      },
    );
    if (FirestoreRest.failedPrecondition(answer)) return false;
    _check(answer);
    return true;
  }

  @override
  SyncRemote records(String uid) => _RestRecords(this, uid);

  /// Through the `deleteSyncData` function, as on a phone: the rules let no
  /// client delete the sync settings.
  @override
  Future<void> deleteAll(String uid) async {
    final answer = await _call('POST', Uri.parse(kDeleteSyncDataUrl));
    if (answer.status != 200) throw const SyncException(SyncFailure.network);
  }

  @override
  Stream<void> watch(String uid) {
    String? seen;
    var first = true;
    return Stream<void>.periodic(pollEvery)
        .asyncMap((_) async {
          try {
            final newest = await _newest(uid);
            if (newest == null) return false;
            final (id, stamp, data) = newest;
            final changed = !first && stamp != seen;
            first = false;
            seen = stamp;
            return changed && !ownWritesOnly([(id, data)], _written);
          } on Object {
            return false;
          }
        })
        .where((changed) => changed)
        .map((_) {});
  }

  /// The record changed last: its id, when it changed, and what it holds.
  Future<(String, String, Map<String, dynamic>)?> _newest(String uid) async {
    final answer = await _call(
      'POST',
      Uri.parse('$_root/users/$uid:runQuery'),
      body: {
        'structuredQuery': {
          'from': [
            {'collectionId': 'records'},
          ],
          'orderBy': [
            {
              'field': {'fieldPath': 'updatedAt'},
              'direction': 'DESCENDING',
            },
          ],
          'limit': 1,
        },
      },
    );
    _check(answer);
    final rows = answer.body;
    if (rows is! List) return null;
    for (final row in rows) {
      final document = row is Map ? row['document'] : null;
      if (document is! Map) continue;
      final name = '${document['name']}';
      return (
        name.split('/').last,
        '${document['updateTime']}',
        _record(FirestoreRest.fields(document)),
      );
    }
    return null;
  }

  Future<Map<String, RemoteEntry>> _fetchAll(String uid) async {
    final entries = <String, RemoteEntry>{};
    String? page;
    do {
      final answer = await _call(
        'GET',
        Uri.parse(
          '$_root/users/$uid/records',
        ).replace(queryParameters: {'pageSize': '300', 'pageToken': ?page}),
      );
      _check(answer);
      final body = answer.body;
      final documents = body is Map ? body['documents'] : null;
      if (documents is List) {
        for (final document in documents) {
          if (document is! Map) continue;
          final data = _record(FirestoreRest.fields(document));
          final ciphertext = data['ciphertext'];
          if (ciphertext is! String) continue;
          entries['${document['name']}'.split('/').last] = RemoteEntry(
            ciphertext: ciphertext,
            deleted: data['deleted'] == true,
          );
        }
      }
      page = body is Map ? body['nextPageToken'] as String? : null;
    } while (page != null && page.isNotEmpty);
    return entries;
  }

  Future<void> _put(String uid, String documentId, RemoteEntry entry) async {
    _written[documentId] = writtenAs({
      'ciphertext': entry.ciphertext,
      'deleted': entry.deleted,
    });
    final answer = await _call(
      'POST',
      Uri.parse('$_root:commit'),
      body: {
        'writes': [
          {
            'update': {
              'name': _name('users/$uid/records/$documentId'),
              'fields': {
                'ciphertext': {'stringValue': entry.ciphertext},
                'deleted': {'booleanValue': entry.deleted},
              },
            },
            'updateTransforms': [
              {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
            ],
          },
        ],
      },
    );
    _check(answer);
  }

  static Map<String, dynamic> _record(Map<String, Object?> fields) => {
    'ciphertext': FirestoreRest.string(fields['ciphertext']),
    'deleted': FirestoreRest.value(fields['deleted']) == true,
  };

  /// Throws for an answer that is not a success: a refusal - no Pro, or not
  /// this account's copy - as such, anything else as the network failing.
  static void _check(FirestoreAnswer answer) {
    if (answer.status >= 200 && answer.status < 300) return;
    if (answer.status == 401 || answer.status == 403) {
      throw const SyncException(SyncFailure.notPro);
    }
    throw const SyncException(SyncFailure.network);
  }
}

class _RestRecords implements SyncRemote {
  _RestRecords(this._cloud, this._uid);

  final RestSyncCloud _cloud;
  final String _uid;

  @override
  Future<Map<String, RemoteEntry>> fetchAll() => _cloud._fetchAll(_uid);

  @override
  Future<void> put(String documentId, RemoteEntry entry) =>
      _cloud._put(_uid, documentId, entry);
}

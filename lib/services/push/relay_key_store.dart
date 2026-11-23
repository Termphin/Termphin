import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firestore_rest.dart';

/// A server holding a key to this account: what the list of servers in
/// Settings shows, and how a live status report finds its machine.
class RelayServer {
  const RelayServer({
    required this.keyId,
    required this.label,
    this.profileId,
    this.createdAt,
    this.lastSentAt,
  });

  final String keyId;
  final String label;
  final String? profileId;
  final DateTime? createdAt;
  final DateTime? lastSentAt;
}

/// The account's relay keys in `relayKeys`: registering one, taking one
/// away, and the list of them. Firestore's plugin on a phone, its REST API
/// on a computer ([RestRelayKeyStore]).
abstract interface class RelayKeyStore {
  /// Registers key [id] for [uid]: its secret's hash, the [label] it is
  /// listed under and the machine it was made for.
  Future<void> create(
    String id, {
    required String uid,
    required String secretHash,
    required String label,
    String? profileId,
  });

  Future<void> delete(String id);

  /// The account's keys, newest first, again whenever they change.
  Stream<List<RelayServer>> list(String uid);
}

/// Newest first, the way the list is shown.
List<RelayServer> newestFirst(List<RelayServer> servers) => servers
  ..sort(
    (a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
  );

class FirestoreRelayKeyStore implements RelayKeyStore {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Future<void> create(
    String id, {
    required String uid,
    required String secretHash,
    required String label,
    String? profileId,
  }) => _db.collection('relayKeys').doc(id).set({
    'uid': uid,
    'secretHash': secretHash,
    'label': label,
    'profileId': ?profileId,
    'createdAt': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> delete(String id) =>
      _db.collection('relayKeys').doc(id).delete();

  @override
  Stream<List<RelayServer>> list(String uid) => _db
      .collection('relayKeys')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map(
        (snapshot) => newestFirst([
          for (final document in snapshot.docs)
            RelayServer(
              keyId: document.id,
              label: document.data()['label'] as String? ?? '',
              profileId: document.data()['profileId'] as String?,
              createdAt: (document.data()['createdAt'] as Timestamp?)?.toDate(),
              lastSentAt: (document.data()['lastSentAt'] as Timestamp?)
                  ?.toDate(),
            ),
        ]),
      );
}

/// The same `relayKeys` through Firestore's REST API, for a computer. The
/// API has no live listener, so [list] reads the keys at once and again
/// every [pollEvery], and after every [create] or [delete] made here.
class RestRelayKeyStore implements RelayKeyStore {
  RestRelayKeyStore({
    FirestoreSend? send,
    Future<String?> Function()? token,
    this.pollEvery = const Duration(minutes: 2),
  }) : _rest = FirestoreRest(send: send, token: token);

  final FirestoreRest _rest;
  final Duration pollEvery;
  final _changed = StreamController<void>.broadcast();

  @override
  Future<void> create(
    String id, {
    required String uid,
    required String secretHash,
    required String label,
    String? profileId,
  }) async {
    final answer = await _rest.call(
      'POST',
      Uri.parse('${FirestoreRest.root}:commit'),
      body: {
        'writes': [
          {
            'update': {
              'name': FirestoreRest.name('relayKeys/$id'),
              'fields': {
                'uid': {'stringValue': uid},
                'secretHash': {'stringValue': secretHash},
                'label': {'stringValue': label},
                if (profileId != null) 'profileId': {'stringValue': profileId},
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
    FirestoreRest.check(answer);
    _changed.add(null);
  }

  @override
  Future<void> delete(String id) async {
    final answer = await _rest.call(
      'DELETE',
      Uri.parse('${FirestoreRest.root}/relayKeys/$id'),
    );
    FirestoreRest.check(answer);
    _changed.add(null);
  }

  /// The account's keys now: the documents whose `uid` is [uid], which is
  /// all the security rules let it read.
  Future<List<RelayServer>> fetch(String uid) async {
    final answer = await _rest.call(
      'POST',
      Uri.parse('${FirestoreRest.root}:runQuery'),
      body: {
        'structuredQuery': {
          'from': [
            {'collectionId': 'relayKeys'},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'uid'},
              'op': 'EQUAL',
              'value': {'stringValue': uid},
            },
          },
        },
      },
    );
    FirestoreRest.check(answer);
    final rows = answer.body;
    return newestFirst([
      if (rows is List)
        for (final row in rows)
          if (row is Map && row['document'] is Map)
            _server((row['document'] as Map).cast<String, Object?>()),
    ]);
  }

  static RelayServer _server(Map<String, Object?> document) {
    final fields = FirestoreRest.fields(document);
    return RelayServer(
      keyId: FirestoreRest.id(document),
      label: FirestoreRest.string(fields['label']) ?? '',
      profileId: FirestoreRest.string(fields['profileId']),
      createdAt: FirestoreRest.timestamp(fields['createdAt']),
      lastSentAt: FirestoreRest.timestamp(fields['lastSentAt']),
    );
  }

  @override
  Stream<List<RelayServer>> list(String uid) {
    // ignore: close_sinks
    late final StreamController<List<RelayServer>> controller;
    Timer? timer;
    StreamSubscription<void>? changes;
    Future<void> read() async {
      try {
        final servers = await fetch(uid);
        if (!controller.isClosed) controller.add(servers);
      } on Object catch (error) {
        if (!controller.isClosed) controller.addError(error);
      }
    }

    controller = StreamController<List<RelayServer>>(
      onListen: () {
        unawaited(read());
        timer = Timer.periodic(pollEvery, (_) => unawaited(read()));
        changes = _changed.stream.listen((_) => unawaited(read()));
      },
      onCancel: () async {
        timer?.cancel();
        await changes?.cancel();
      },
    );
    return controller.stream;
  }
}

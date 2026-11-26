import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firestore_rest.dart';

/// A server holding a key to this account: what the lists of machines in
/// Termphin Pro show, and how a live status report finds its machine. Its
/// switches - [notify] for push, [live] for live status - are the account's,
/// read by the relay and the realtime backend on every push and report.
class RelayServer {
  const RelayServer({
    required this.keyId,
    required this.label,
    this.profileId,
    this.createdAt,
    this.lastSentAt,
    this.notify,
    this.live,
  });

  final String keyId;
  final String label;
  final String? profileId;
  final DateTime? createdAt;
  final DateTime? lastSentAt;

  /// Whether the machine's pushes go out; null for a key from before the
  /// switch existed, which the relay sends from - whether that machine
  /// really had notifications is its server's quiet flag, settled on its
  /// next connect ([PushService]).
  final bool? notify;

  /// Whether the machine shows its live status; null for a key from before
  /// the switch existed, which the realtime backend still takes reports
  /// for. Whether such a machine really has live status is settled by the
  /// device holding its presence key ([PushService]) and written back.
  final bool? live;
}

/// The account's relay keys in `relayKeys`: registering one, taking one
/// away, and the list of them. Firestore's plugin on a phone, its REST API
/// on a computer ([RestRelayKeyStore]).
abstract interface class RelayKeyStore {
  /// Registers key [id] for [uid]: its secret's hash, the [label] it is
  /// listed under, the machine it was made for and what it may do.
  Future<void> create(
    String id, {
    required String uid,
    required String secretHash,
    required String label,
    String? profileId,
    bool notify = true,
    bool live = false,
  });

  /// Switches what the machine of key [id] may do, at once: the switches
  /// given, leaving the other as it is.
  Future<void> setSwitches(String id, {bool? notify, bool? live});

  Future<void> delete(String id);

  /// The account's keys, newest first, again whenever they change.
  Stream<List<RelayServer>> list(String uid);

  /// The account's keys as the server has them now - never a cached copy,
  /// which may be stale or empty: what deciding to take a machine's setup
  /// away rests on. Throws when the server cannot be reached.
  Future<List<RelayServer>> current(String uid);
}

/// The fields [RelayKeyStore.setSwitches] writes: the switches given.
Map<String, bool> switchFields({bool? notify, bool? live}) => {
  'notify': ?notify,
  'live': ?live,
};

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
    bool notify = true,
    bool live = false,
  }) => _db.collection('relayKeys').doc(id).set({
    'uid': uid,
    'secretHash': secretHash,
    'label': label,
    'profileId': ?profileId,
    'notify': notify,
    'live': live,
    'createdAt': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> setSwitches(String id, {bool? notify, bool? live}) async {
    final fields = switchFields(notify: notify, live: live);
    if (fields.isEmpty) return;
    await _db.collection('relayKeys').doc(id).update(fields);
  }

  @override
  Future<void> delete(String id) =>
      _db.collection('relayKeys').doc(id).delete();

  @override
  Future<List<RelayServer>> current(String uid) async => _servers(
    await _db
        .collection('relayKeys')
        .where('uid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server)),
  );

  @override
  Stream<List<RelayServer>> list(String uid) => _db
      .collection('relayKeys')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map(_servers);

  static List<RelayServer> _servers(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => newestFirst([
    for (final document in snapshot.docs)
      RelayServer(
        keyId: document.id,
        label: document.data()['label'] as String? ?? '',
        profileId: document.data()['profileId'] as String?,
        createdAt: (document.data()['createdAt'] as Timestamp?)?.toDate(),
        lastSentAt: (document.data()['lastSentAt'] as Timestamp?)?.toDate(),
        notify: document.data()['notify'] as bool?,
        live: document.data()['live'] as bool?,
      ),
  ]);
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
    bool notify = true,
    bool live = false,
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
                'notify': {'booleanValue': notify},
                'live': {'booleanValue': live},
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
  Future<void> setSwitches(String id, {bool? notify, bool? live}) async {
    final fields = switchFields(notify: notify, live: live);
    if (fields.isEmpty) return;
    final answer = await _rest.call(
      'POST',
      Uri.parse('${FirestoreRest.root}:commit'),
      body: {
        'writes': [
          {
            'update': {
              'name': FirestoreRest.name('relayKeys/$id'),
              'fields': {
                for (final MapEntry(:key, :value) in fields.entries)
                  key: {'booleanValue': value},
              },
            },
            'updateMask': {'fieldPaths': fields.keys.toList()},
            'currentDocument': {'exists': true},
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

  @override
  Future<List<RelayServer>> current(String uid) => fetch(uid);

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
      notify: switch (FirestoreRest.value(fields['notify'])) {
        final bool notify => notify,
        _ => null,
      },
      live: switch (FirestoreRest.value(fields['live'])) {
        final bool live => live,
        _ => null,
      },
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

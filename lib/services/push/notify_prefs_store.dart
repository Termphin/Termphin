import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firestore_rest.dart';

/// How many of the account's devices the relay reaches: the ones that
/// registered most lately. The list shows no more than that, so it never
/// offers a switch for a device the relay would skip anyway.
const kRelayMaxDevices = 10;

/// The longest name a device may be given, as the security rules allow.
const kNotifyDeviceNameMax = 40;

/// What a phone or tablet is, for its icon and the name it is listed under.
/// A computer is never one: only phones and tablets get pushes.
enum NotifyDeviceKind { phone, tablet }

/// One phone or tablet the relay can reach: its registration in
/// `users/{uid}/devices/{id}` and, when it has one, its own settings in
/// `users/{uid}/notifyPrefs/{id}` - whether it gets notifications, and what
/// kind of device it is. Any of the account's devices, a computer too, can
/// switch it; the relay reads it on every push, so a change counts at once.
class NotifyDestination {
  const NotifyDestination({
    required this.id,
    required this.platform,
    this.kind,
    this.enabled = true,
    this.hasPrefs = false,
    this.registeredAt,
    this.name,
  });

  /// The device's install id.
  final String id;

  /// `android` or `ios`, as the device registered.
  final String platform;

  /// Null for a device whose app predates per-device settings.
  final NotifyDeviceKind? kind;

  final bool enabled;

  /// Whether the settings document exists; without it the device follows
  /// the account's settings and gets everything.
  final bool hasPrefs;

  /// When the device last registered its token.
  final DateTime? registeredAt;

  /// The name the user gave it, listed instead of its kind and platform;
  /// null until they do.
  final String? name;

  /// The list in the order the relay picks devices: latest registration
  /// first, at most [kRelayMaxDevices].
  static List<NotifyDestination> listed(Iterable<NotifyDestination> all) =>
      (all.toList()..sort(
            (a, b) => (b.registeredAt ?? DateTime(0)).compareTo(
              a.registeredAt ?? DateTime(0),
            ),
          ))
          .take(kRelayMaxDevices)
          .toList();
}

NotifyDeviceKind? _kind(Object? name) => switch (name) {
  'phone' => NotifyDeviceKind.phone,
  'tablet' => NotifyDeviceKind.tablet,
  _ => null,
};

/// The account's phones and tablets and their notification settings.
/// Firestore's plugin on a phone, its REST API on a computer
/// ([RestNotifyPrefsStore]).
abstract interface class NotifyPrefsStore {
  /// The account's devices with their settings, again whenever they change.
  Stream<List<NotifyDestination>> list(String uid);

  /// Records what device [id] is - its own call, on registering - and
  /// gives it a settings document switched on when it has none. Leaves an
  /// existing document's switch alone, so a device switched off from
  /// elsewhere stays off when its token is refreshed.
  Future<void> describe(String uid, String id, NotifyDeviceKind kind);

  /// Switches [destination] on or off: whether it gets notifications.
  Future<void> setEnabled(
    String uid,
    NotifyDestination destination,
    bool enabled,
  );

  /// Gives [destination] its own [name], or takes it away with null, so it
  /// is listed by its kind and platform again.
  Future<void> setName(String uid, NotifyDestination destination, String? name);
}

/// [name] as stored: trimmed, null when nothing is left of it.
String? cleanDeviceName(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class FirestoreNotifyPrefsStore implements NotifyPrefsStore {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _prefs(String uid, String id) =>
      _db.collection('users').doc(uid).collection('notifyPrefs').doc(id);

  @override
  Stream<List<NotifyDestination>> list(String uid) {
    final user = _db.collection('users').doc(uid);
    QuerySnapshot<Map<String, dynamic>>? devices;
    QuerySnapshot<Map<String, dynamic>>? prefs;
    // ignore: close_sinks
    late final StreamController<List<NotifyDestination>> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    void emit() {
      final registered = devices;
      final settings = prefs;
      if (registered == null || settings == null || controller.isClosed) {
        return;
      }
      final byId = {
        for (final document in settings.docs) document.id: document.data(),
      };
      controller.add(
        NotifyDestination.listed([
          for (final document in registered.docs)
            _destination(document.id, document.data(), byId[document.id]),
        ]),
      );
    }

    controller = StreamController<List<NotifyDestination>>(
      onListen: () {
        subscriptions
          ..add(
            user
                .collection('devices')
                .orderBy('updatedAt', descending: true)
                .limit(kRelayMaxDevices)
                .snapshots()
                .listen((snapshot) {
                  devices = snapshot;
                  emit();
                }, onError: controller.addError),
          )
          ..add(
            user.collection('notifyPrefs').snapshots().listen((snapshot) {
              prefs = snapshot;
              emit();
            }, onError: controller.addError),
          );
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  static NotifyDestination _destination(
    String id,
    Map<String, dynamic> device,
    Map<String, dynamic>? prefs,
  ) => NotifyDestination(
    id: id,
    platform: device['platform'] as String? ?? '',
    registeredAt: (device['updatedAt'] as Timestamp?)?.toDate(),
    kind: _kind(prefs?['kind']),
    enabled: prefs?['enabled'] != false,
    hasPrefs: prefs != null,
    name: cleanDeviceName(prefs?['name'] as String?),
  );

  @override
  Future<void> describe(String uid, String id, NotifyDeviceKind kind) async {
    final reference = _prefs(uid, id);
    final existing = await reference.get();
    if (!existing.exists) {
      await reference.set({
        'kind': kind.name,
        'enabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (existing.data()?['kind'] != kind.name) {
      await reference.update({
        'kind': kind.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Future<void> setEnabled(
    String uid,
    NotifyDestination destination,
    bool enabled,
  ) => _prefs(uid, destination.id).set({
    'enabled': enabled,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  @override
  Future<void> setName(
    String uid,
    NotifyDestination destination,
    String? name,
  ) {
    final cleaned = cleanDeviceName(name);
    return _prefs(uid, destination.id).set({
      'name': cleaned ?? FieldValue.delete(),
      if (!destination.hasPrefs) 'enabled': destination.enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// The same documents through Firestore's REST API, for a computer. The API
/// has no live listener, so [list] reads them at once, again every
/// [pollEvery], and after every change made here.
class RestNotifyPrefsStore implements NotifyPrefsStore {
  RestNotifyPrefsStore({
    FirestoreSend? send,
    Future<String?> Function()? token,
    this.pollEvery = const Duration(minutes: 2),
  }) : _rest = FirestoreRest(send: send, token: token);

  final FirestoreRest _rest;
  final Duration pollEvery;
  final _changed = StreamController<void>.broadcast();

  /// The account's devices with their settings now: the newest
  /// registrations, as the relay picks them, and the settings of those
  /// alone.
  Future<List<NotifyDestination>> fetch(String uid) async {
    final answer = await _rest.call(
      'GET',
      Uri.parse(
        '${FirestoreRest.root}/users/$uid/devices'
        '?orderBy=updatedAt%20desc&pageSize=$kRelayMaxDevices',
      ),
    );
    FirestoreRest.check(answer);
    final body = answer.body;
    final listed = body is Map ? body['documents'] : null;
    final devices = listed is List ? listed : const <Object?>[];
    final prefs = await _prefsOf(uid, [
      for (final document in devices) FirestoreRest.id(document),
    ]);
    return NotifyDestination.listed([
      for (final document in devices)
        _destination(
          FirestoreRest.id(document),
          FirestoreRest.fields(document),
          prefs[FirestoreRest.id(document)],
        ),
    ]);
  }

  /// The settings documents of devices [ids] that have one, by id.
  Future<Map<String, Map<String, Object?>>> _prefsOf(
    String uid,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final answer = await _rest.call(
      'POST',
      Uri.parse('${FirestoreRest.root}:batchGet'),
      body: {
        'documents': [
          for (final id in ids)
            FirestoreRest.name('users/$uid/notifyPrefs/$id'),
        ],
      },
    );
    FirestoreRest.check(answer);
    final rows = answer.body;
    return {
      if (rows is List)
        for (final row in rows)
          if (row is Map && row['found'] is Map)
            FirestoreRest.id(row['found']): FirestoreRest.fields(row['found']),
    };
  }

  static NotifyDestination _destination(
    String id,
    Map<String, Object?> device,
    Map<String, Object?>? prefs,
  ) {
    return NotifyDestination(
      id: id,
      platform: FirestoreRest.string(device['platform']) ?? '',
      registeredAt: FirestoreRest.timestamp(device['updatedAt']),
      kind: _kind(FirestoreRest.string(prefs?['kind'])),
      enabled: FirestoreRest.value(prefs?['enabled']) != false,
      hasPrefs: prefs != null,
      name: cleanDeviceName(FirestoreRest.string(prefs?['name'])),
    );
  }

  /// Writes [fields] (REST-typed) and [transforms] onto device [id]'s
  /// settings, creating them when missing, with the server's time. The
  /// fields in [cleared] are taken off the document.
  Future<void> _write(
    String uid,
    String id,
    Map<String, Object?> fields, {
    List<Map<String, Object?>> transforms = const [],
    List<String> cleared = const [],
  }) async {
    final answer = await _rest.call(
      'POST',
      Uri.parse('${FirestoreRest.root}:commit'),
      body: {
        'writes': [
          {
            'update': {
              'name': FirestoreRest.name('users/$uid/notifyPrefs/$id'),
              'fields': fields,
            },
            'updateMask': {
              'fieldPaths': [...fields.keys, ...cleared],
            },
            'updateTransforms': [
              ...transforms,
              {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
            ],
          },
        ],
      },
    );
    FirestoreRest.check(answer);
    _changed.add(null);
  }

  @override
  Future<void> describe(String uid, String id, NotifyDeviceKind kind) async {
    final answer = await _rest.call(
      'GET',
      Uri.parse('${FirestoreRest.root}/users/$uid/notifyPrefs/$id'),
    );
    if (answer.status != 404) FirestoreRest.check(answer);
    await _write(uid, id, {
      'kind': {'stringValue': kind.name},
      if (answer.status == 404) 'enabled': {'booleanValue': true},
    });
  }

  @override
  Future<void> setEnabled(
    String uid,
    NotifyDestination destination,
    bool enabled,
  ) => _write(uid, destination.id, {
    'enabled': {'booleanValue': enabled},
  });

  @override
  Future<void> setName(
    String uid,
    NotifyDestination destination,
    String? name,
  ) {
    final cleaned = cleanDeviceName(name);
    return _write(
      uid,
      destination.id,
      {
        'name': ?(cleaned == null ? null : {'stringValue': cleaned}),
        if (!destination.hasPrefs)
          'enabled': {'booleanValue': destination.enabled},
      },
      cleared: [if (cleaned == null) 'name'],
    );
  }

  @override
  Stream<List<NotifyDestination>> list(String uid) {
    // ignore: close_sinks
    late final StreamController<List<NotifyDestination>> controller;
    Timer? timer;
    StreamSubscription<void>? changes;
    Future<void> read() async {
      try {
        final destinations = await fetch(uid);
        if (!controller.isClosed) controller.add(destinations);
      } on Object catch (error) {
        if (!controller.isClosed) controller.addError(error);
      }
    }

    controller = StreamController<List<NotifyDestination>>(
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

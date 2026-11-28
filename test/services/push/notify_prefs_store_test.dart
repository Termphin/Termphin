import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/firebase/firestore_rest.dart';
import 'package:termphin/services/push/notify_prefs_store.dart';

void main() {
  late List<(String, Uri, Object?)> calls;
  late List<FirestoreAnswer> replies;

  setUp(() {
    calls = [];
    replies = [];
  });

  RestNotifyPrefsStore store() => RestNotifyPrefsStore(
    send: (method, url, {body, required token}) async {
      calls.add((method, url, body));
      return replies.isEmpty ? (status: 200, body: null) : replies.removeAt(0);
    },
    token: () async => 'tok',
  );

  Map<String, Object?> document(String path, Map<String, Object?> fields) => {
    'name':
        'projects/termphin-hexeosoft/databases/(default)/documents/users/u1/$path',
    'fields': fields,
  };

  Map<String, Object?> device(String id, String platform, String at) =>
      document('devices/$id', {
        'token': {'stringValue': 'fcm-$id'},
        'platform': {'stringValue': platform},
        'updatedAt': {'timestampValue': at},
      });

  Map<String, Object?> write(Object? body) =>
      (((body! as Map)['writes'] as List).single as Map)
          .cast<String, Object?>();

  test(
    'lists the newest devices with their own settings, as the relay picks them',
    () async {
      replies
        ..add((
          status: 200,
          body: {
            'documents': [
              device('new', 'ios', '2026-11-20T10:00:00Z'),
              device('old', 'android', '2026-11-01T10:00:00Z'),
            ],
          },
        ))
        ..add((
          status: 200,
          body: [
            {
              'found': document('notifyPrefs/old', {
                'kind': {'stringValue': 'tablet'},
                'enabled': {'booleanValue': false},
              }),
            },
            {
              'missing':
                  'projects/termphin-hexeosoft/databases/(default)/documents/users/u1/notifyPrefs/new',
            },
          ],
        ));
      final destinations = await store().fetch('u1');
      expect(destinations.map((d) => d.id), ['new', 'old']);
      final fresh = destinations.first;
      expect(fresh.platform, 'ios');
      expect(fresh.hasPrefs, isFalse);
      expect(fresh.enabled, isTrue);
      expect(fresh.kind, isNull);
      final old = destinations.last;
      expect(old.kind, NotifyDeviceKind.tablet);
      expect(old.enabled, isFalse);
      expect(calls.first.$2.queryParameters, {
        'orderBy': 'updatedAt desc',
        'pageSize': '$kRelayMaxDevices',
      });
      expect((calls.last.$3! as Map)['documents'], [
        endsWith('/users/u1/notifyPrefs/new'),
        endsWith('/users/u1/notifyPrefs/old'),
      ]);
    },
  );

  test('an account with no devices reads no settings', () async {
    replies.add((status: 200, body: <String, Object?>{}));
    expect(await store().fetch('u1'), isEmpty);
    expect(calls, hasLength(1));
  });

  test('lists no more devices than the relay reaches', () {
    final all = [
      for (var i = 0; i < kRelayMaxDevices + 3; i++)
        NotifyDestination(
          id: 'd$i',
          platform: 'android',
          registeredAt: DateTime.utc(2026, 1, 1 + i),
        ),
    ];
    final listed = NotifyDestination.listed(all);
    expect(listed, hasLength(kRelayMaxDevices));
    expect(listed.first.id, 'd${kRelayMaxDevices + 2}');
  });

  test('switching a device off writes only its switch', () async {
    await store().setEnabled(
      'u1',
      const NotifyDestination(id: 'tablet', platform: 'ios', hasPrefs: true),
      false,
    );
    final sent = write(calls.single.$3);
    expect(
      (sent['update']! as Map)['name'],
      endsWith('/users/u1/notifyPrefs/tablet'),
    );
    expect((sent['updateMask']! as Map)['fieldPaths'], ['enabled']);
  });

  test(
    'describing a device switches it on only when it has no settings',
    () async {
      replies.add((status: 404, body: null));
      await store().describe('u1', 'phone', NotifyDeviceKind.phone);
      expect((write(calls.last.$3)['updateMask']! as Map)['fieldPaths'], [
        'kind',
        'enabled',
      ]);
      replies.add((status: 200, body: document('notifyPrefs/phone', {})));
      await store().describe('u1', 'phone', NotifyDeviceKind.tablet);
      expect((write(calls.last.$3)['updateMask']! as Map)['fieldPaths'], [
        'kind',
      ]);
    },
  );

  test('a refused write is reported, not swallowed', () async {
    replies.add((status: 403, body: null));
    await expectLater(
      store().setEnabled(
        'u1',
        const NotifyDestination(id: 'phone', platform: 'android'),
        true,
      ),
      throwsA(isA<FirestoreRestException>()),
    );
  });

  test('naming a device writes only its name, trimmed', () async {
    await store().setName(
      'u1',
      const NotifyDestination(id: 'tablet', platform: 'ios', hasPrefs: true),
      '  Kitchen iPad ',
    );
    final sent = write(calls.single.$3);
    expect((sent['updateMask']! as Map)['fieldPaths'], ['name']);
    expect(((sent['update']! as Map)['fields'] as Map)['name'], {
      'stringValue': 'Kitchen iPad',
    });
  });

  test('a blank name takes the device\'s name away', () async {
    await store().setName(
      'u1',
      const NotifyDestination(id: 'tablet', platform: 'ios', hasPrefs: true),
      '   ',
    );
    final sent = write(calls.single.$3);
    expect((sent['updateMask']! as Map)['fieldPaths'], ['name']);
    expect(((sent['update']! as Map)['fields'] as Map), isEmpty);
  });

  test('naming a device with no settings yet keeps it switched on', () async {
    await store().setName(
      'u1',
      const NotifyDestination(id: 'phone', platform: 'android'),
      'Work phone',
    );
    expect(
      (write(calls.single.$3)['updateMask']! as Map)['fieldPaths'],
      unorderedEquals(['name', 'enabled']),
    );
  });

  test('a device is listed with the name it was given', () async {
    replies
      ..add((
        status: 200,
        body: {
          'documents': [device('phone', 'android', '2026-11-27T10:00:00Z')],
        },
      ))
      ..add((
        status: 200,
        body: [
          {
            'found': document('notifyPrefs/phone', {
              'enabled': {'booleanValue': true},
              'name': {'stringValue': 'Work phone'},
            }),
          },
        ],
      ));
    final listed = await store().fetch('u1');
    expect(listed.single.name, 'Work phone');
  });
}

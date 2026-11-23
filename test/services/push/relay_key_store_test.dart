import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/firebase/firestore_rest.dart';
import 'package:termphin/services/push/relay_key_store.dart';

void main() {
  late List<(String, Uri, Object?)> calls;
  late List<FirestoreAnswer> replies;

  setUp(() {
    calls = [];
    replies = [];
  });

  RestRelayKeyStore store() => RestRelayKeyStore(
    send: (method, url, {body, required token}) async {
      calls.add((method, url, body));
      return replies.isEmpty ? (status: 200, body: null) : replies.removeAt(0);
    },
    token: () async => 'tok',
  );

  Map<String, Object?> key(String id, String created, {String? profile}) => {
    'document': {
      'name':
          'projects/termphin-hexeosoft/databases/(default)/documents/relayKeys/$id',
      'fields': {
        'uid': {'stringValue': 'u1'},
        'label': {'stringValue': 'web-01'},
        'profileId': ?(profile == null ? null : {'stringValue': profile}),
        'createdAt': {'timestampValue': created},
      },
    },
  };

  test('lists the account own keys, newest first', () async {
    replies.add((
      status: 200,
      body: [
        key('old', '2026-11-01T10:00:00Z', profile: 'p1'),
        key('new', '2026-11-20T10:00:00Z'),
      ],
    ));
    final servers = await store().fetch('u1');
    expect(servers.map((s) => s.keyId), ['new', 'old']);
    expect(servers.last.profileId, 'p1');
    expect(servers.first.label, 'web-01');
    final query = (calls.single.$3! as Map)['structuredQuery'] as Map;
    expect(((query['where'] as Map)['fieldFilter'] as Map)['value'], {
      'stringValue': 'u1',
    });
  });

  test(
    'registers a key only where there is none, with the server time',
    () async {
      await store().create(
        'k1',
        uid: 'u1',
        secretHash: 'h' * 64,
        label: 'web-01',
        profileId: 'p1',
      );
      final write = ((calls.single.$3! as Map)['writes'] as List).single as Map;
      expect(write['currentDocument'], {'exists': false});
      expect(
        ((write['update'] as Map)['fields'] as Map).keys,
        containsAll(['uid', 'secretHash', 'label', 'profileId']),
      );
      expect(write['updateTransforms'], [
        {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
      ]);
    },
  );

  test('deletes a key by its document', () async {
    await store().delete('k1');
    expect(calls.single.$1, 'DELETE');
    expect(calls.single.$2.path, endsWith('/relayKeys/k1'));
  });

  test('a refused list surfaces as an error, not as no keys', () async {
    replies.add((status: 403, body: null));
    await expectLater(
      store().fetch('u1'),
      throwsA(isA<FirestoreRestException>()),
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/security/secret_cipher.dart';
import 'package:termphin/services/sync/rest_sync_cloud.dart';
import 'package:termphin/services/sync/sync_engine.dart';
import 'package:termphin/services/sync/sync_service.dart';

import '../../support/fake_master_key_store.dart';

/// Firestore's REST API answering from a script, recording every request.
class FakeFirestore {
  final calls = <(String, Uri, Object?)>[];
  final replies = <FirestoreAnswer>[];

  Future<FirestoreAnswer> send(
    String method,
    Uri url, {
    Object? body,
    required String token,
  }) async {
    calls.add((method, url, body));
    expect(token, 'tok');
    return replies.isEmpty ? (status: 200, body: null) : replies.removeAt(0);
  }
}

Map<String, Object?> record(String id, String ciphertext, String time) => {
  'name':
      'projects/termphin-hexeosoft/databases/(default)/documents/users/u1/records/$id',
  'fields': {
    'ciphertext': {'stringValue': ciphertext},
    'deleted': {'booleanValue': false},
  },
  'updateTime': time,
};

void main() {
  late FakeFirestore firestore;

  setUp(() => firestore = FakeFirestore());

  RestSyncCloud cloud() => RestSyncCloud(
    send: firestore.send,
    token: () async => 'tok',
    pollEvery: const Duration(seconds: 1),
  );

  test('reads the sync settings, or none', () async {
    firestore.replies.add((
      status: 200,
      body: {
        'fields': {
          'salt': {
            'stringValue': base64Encode([1, 2, 3]),
          },
          'iterations': {'integerValue': '600000'},
          'check': {'stringValue': 'chk'},
        },
      },
    ));
    final meta = await cloud().readMeta('u1');
    expect(meta!.salt, Uint8List.fromList([1, 2, 3]));
    expect(meta.iterations, 600000);
    expect(meta.check, 'chk');
    expect(firestore.calls.single.$2.path, endsWith('/users/u1/syncMeta/key'));

    firestore.replies.add((status: 404, body: null));
    expect(await cloud().readMeta('u1'), isNull);
  });

  test('creates the sync settings only where there are none', () async {
    final meta = SyncMeta(
      salt: Uint8List.fromList([9]),
      iterations: 600000,
      check: 'c',
    );
    expect(await cloud().createMeta('u1', meta), isTrue);
    final write =
        ((firestore.calls.single.$3! as Map)['writes'] as List).single as Map;
    expect(write['currentDocument'], {'exists': false});
    expect(
      (write['update'] as Map)['name'],
      endsWith('/users/u1/syncMeta/key'),
    );

    firestore.replies.add((
      status: 400,
      body: {
        'error': {'status': 'FAILED_PRECONDITION'},
      },
    ));
    expect(await cloud().createMeta('u1', meta), isFalse);
  });

  test(
    'pages through every record and writes one with the server time',
    () async {
      firestore.replies
        ..add((
          status: 200,
          body: {
            'documents': [record('a', 'x', 't1')],
            'nextPageToken': 'p2',
          },
        ))
        ..add((
          status: 200,
          body: {
            'documents': [record('b', 'y', 't2')],
          },
        ));
      final records = cloud().records('u1');
      final all = await records.fetchAll();
      expect(all.keys, ['a', 'b']);
      expect(all['b']!.ciphertext, 'y');
      expect(firestore.calls[1].$2.queryParameters['pageToken'], 'p2');

      await records.put('c', const RemoteEntry(ciphertext: 'z', deleted: true));
      final write =
          ((firestore.calls.last.$3! as Map)['writes'] as List).single as Map;
      expect((write['update'] as Map)['fields'], {
        'ciphertext': {'stringValue': 'z'},
        'deleted': {'booleanValue': true},
      });
      expect(write['updateTransforms'], [
        {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
      ]);
    },
  );

  test('a refusal means no Pro', () async {
    firestore.replies.add((status: 403, body: null));
    await expectLater(
      cloud().records('u1').fetchAll(),
      throwsA(
        isA<SyncException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.notPro,
        ),
      ),
    );
  });

  test('watching fires for another device, not for its own writes', () {
    fakeAsync((async) {
      final subject = cloud();
      var fired = 0;
      final subscription = subject.watch('u1').listen((_) => fired++);
      firestore.replies
        ..add((
          status: 200,
          body: [
            {'document': record('a', 'x', 't1')},
          ],
        ))
        ..add((
          status: 200,
          body: [
            {'document': record('a', 'x', 't1')},
          ],
        ))
        ..add((
          status: 200,
          body: [
            {'document': record('b', 'other', 't2')},
          ],
        ));
      async.elapse(const Duration(seconds: 3));
      expect(fired, 1);

      unawaited(
        subject
            .records('u1')
            .put('c', const RemoteEntry(ciphertext: 'mine', deleted: false)),
      );
      async.flushMicrotasks();
      firestore.replies.add((
        status: 200,
        body: [
          {'document': record('c', 'mine', 't3')},
        ],
      ));
      async.elapse(const Duration(seconds: 1));
      expect(fired, 1);
      unawaited(subscription.cancel());
    });
  });

  test(
    'a sealed key vault keeps the key across reads and forgets it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final vault = SealedSyncKeyVault(
        cipher: SecretCipher(store: FakeMasterKeyStore()),
      );
      expect(await vault.read('u1'), isNull);
      await vault.write('u1', Uint8List.fromList([1, 2, 3]));
      expect(await vault.read('u1'), Uint8List.fromList([1, 2, 3]));
      await vault.delete('u1');
      expect(await vault.read('u1'), isNull);
    },
  );
}

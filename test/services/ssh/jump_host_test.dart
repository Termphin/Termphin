import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';
import 'package:termphin/services/storage/profile_storage.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

class _FakeSocket implements SSHSocket {
  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void destroy() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStorage profiles;

  SshService serviceFor() => SshService(
    socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
    knownHosts: KnownHostsStore(cipher: cipherFixture()),
    profiles: profiles,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    profiles = ProfileStorage(cipher: cipherFixture());
  });

  test('a profile pointed at itself is refused, not followed', () async {
    final profile = profileFixture(id: 'a', jumpHostProfileId: 'a');
    await profiles.addProfile(profile);

    await expectLater(
      serviceFor().connectSocket(profile),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('its own jump host'),
        ),
      ),
    );
  });

  test('a jump host that no longer exists fails loudly', () async {
    final profile = profileFixture(id: 'a', jumpHostProfileId: 'deleted');
    await profiles.addProfile(profile);

    await expectLater(
      serviceFor().connectSocket(profile),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('jump host'),
        ),
      ),
    );
  });

  test(
    'a chain that never ends is cut off rather than followed forever',
    () async {
      for (var i = 0; i < 6; i++) {
        await profiles.addProfile(
          profileFixture(
            id: 'p$i',
            name: 'hop $i',
            jumpHostProfileId: 'p${i + 1}',
          ),
        );
      }

      await expectLater(
        serviceFor().connectSocket((await profiles.getProfile('p0'))!),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Too many jump hosts'),
          ),
        ),
      );
    },
  );

  test('no jump host means the socket is opened straight out', () async {
    final profile = profileFixture(id: 'a');
    await profiles.addProfile(profile);

    final service = serviceFor();
    await service.connectSocket(profile);

    expect(service.connectedHost, 'example.com');
  });

  test('every misconfigured chain classifies the same way', () async {
    await profiles.addProfile(
      profileFixture(id: 'self', jumpHostProfileId: 'self'),
    );
    await profiles.addProfile(
      profileFixture(id: 'orphan', jumpHostProfileId: 'gone'),
    );
    for (var i = 0; i < 6; i++) {
      await profiles.addProfile(
        profileFixture(id: 'd$i', jumpHostProfileId: 'd${i + 1}'),
      );
    }

    for (final id in ['self', 'orphan', 'd0']) {
      final profile = (await profiles.getProfile(id))!;
      await expectLater(
        serviceFor().connectSocket(profile),
        throwsA(
          isA<SshConnectException>().having(
            (error) => error.reason,
            'reason',
            SshFailureReason.jumpHostConfig,
          ),
        ),
        reason: id,
      );
    }
  });
}

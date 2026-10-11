import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

/// Throwaway ed25519 keys, generated for this test alone. The encrypted one
/// is protected with [_passphrase].
const _plainPem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBp+hXwaukfWgjzsXDy1V1X/X0Z3W63xo96ObFfKSKQcAAAAIjh+CZd4fgm
XQAAAAtzc2gtZWQyNTUxOQAAACBp+hXwaukfWgjzsXDy1V1X/X0Z3W63xo96ObFfKSKQcA
AAAEAXFMpGbQPub59aA1lyylU/pJuEQvagiIL/3Dnl5Dnw+Gn6FfBq6R9aCPOxcPLVXVf9
fRndbrfGj3o5sV8pIpBwAAAABHRlc3QB
-----END OPENSSH PRIVATE KEY-----''';

const _encryptedPem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCSY44x2L
MDwZvc7WHOEpKXAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAICbGWOGfsaeOd+HT
Jsg4hx5tdlRWEmbSDgxyboxeF7JvAAAAkKRaQligET6L0yl7MiwxZRYL6wQqmePmoyfw60
anQJcpxsjsh9mmKH32kpjq22sC+/QTeaVm1i6K487D4WO2IwF21ABq2aHhhcJLaxwSoYo8
pNz8xu5JX4rwPjdpZjrmanNd11zspgMU7B20zYZ8lJ9ZtcgkMiq7GR9ErRbs+WOTbWvGLz
hNxjEFNKbMMVTljQ==
-----END OPENSSH PRIVATE KEY-----''';

const _passphrase = 'correct horse';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a key with no passphrase resolves to an identity', () async {
    final identities = await resolveIdentities(
      profileFixture(authMethod: AuthMethod.privateKey, privateKey: _plainPem),
    );

    expect(identities, isNotNull);
    expect(identities, hasLength(1));
  });

  test('an encrypted key resolves when the passphrase is right', () async {
    final identities = await resolveIdentities(
      profileFixture(
        authMethod: AuthMethod.privateKey,
        privateKey: _encryptedPem,
        passphrase: _passphrase,
      ),
    );

    expect(identities, hasLength(1));
  });

  test('a wrong passphrase reports keyPassphrase, not protocol', () async {
    await expectLater(
      resolveIdentities(
        profileFixture(
          authMethod: AuthMethod.privateKey,
          privateKey: _encryptedPem,
          passphrase: 'not it',
        ),
      ),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.reason,
          'reason',
          SshFailureReason.keyPassphrase,
        ),
      ),
    );
  });

  test('an encrypted key with no passphrase reports keyPassphrase', () async {
    await expectLater(
      resolveIdentities(
        profileFixture(
          authMethod: AuthMethod.privateKey,
          privateKey: _encryptedPem,
        ),
      ),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.reason,
          'reason',
          SshFailureReason.keyPassphrase,
        ),
      ),
    );
  });

  test('an unreadable key reports keyInvalid', () async {
    await expectLater(
      resolveIdentities(
        profileFixture(
          authMethod: AuthMethod.privateKey,
          privateKey: 'this is not a key',
        ),
      ),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.reason,
          'reason',
          SshFailureReason.keyInvalid,
        ),
      ),
    );
  });

  test(
    'a key that is well-formed PEM but damaged reports keyInvalid',
    () async {
      const damaged =
          '-----BEGIN OPENSSH PRIVATE KEY-----\n'
          'bm90IGFuIG9wZW5zc2gga2V5IGF0IGFsbA==\n'
          '-----END OPENSSH PRIVATE KEY-----';

      await expectLater(
        resolveIdentities(
          profileFixture(
            authMethod: AuthMethod.privateKey,
            privateKey: damaged,
          ),
        ),
        throwsA(
          isA<SshConnectException>().having(
            (e) => e.reason,
            'reason',
            SshFailureReason.keyInvalid,
          ),
        ),
      );
    },
  );

  test(
    'a key id that is no longer in the manager reports keyMissing',
    () async {
      await expectLater(
        resolveIdentities(
          profileFixture(authMethod: AuthMethod.privateKey, sshKeyId: 'gone'),
          keyStorage: SshKeyStorage(cipher: cipherFixture()),
        ),
        throwsA(
          isA<SshConnectException>().having(
            (e) => e.reason,
            'reason',
            SshFailureReason.keyMissing,
          ),
        ),
      );
    },
  );

  test('a stored key is read out of the key manager', () async {
    final storage = SshKeyStorage(cipher: cipherFixture());
    await storage.saveKeys([sshKeyFixture(id: 'k1', privateKeyPem: _plainPem)]);

    final identities = await resolveIdentities(
      profileFixture(authMethod: AuthMethod.privateKey, sshKeyId: 'k1'),
      keyStorage: storage,
    );

    expect(identities, hasLength(1));
  });

  test('a key type dartssh2 does not implement reports keyInvalid', () async {
    const dsa =
        '-----BEGIN DSA PRIVATE KEY-----\n'
        'bm90IGltcGxlbWVudGVkIGJ5IGRhcnRzc2gy\n'
        '-----END DSA PRIVATE KEY-----';

    await expectLater(
      resolveIdentities(
        profileFixture(authMethod: AuthMethod.privateKey, privateKey: dsa),
      ),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.reason,
          'reason',
          SshFailureReason.keyInvalid,
        ),
      ),
    );
  });

  test('an empty passphrase is treated as no passphrase', () async {
    final identities = await resolveIdentities(
      profileFixture(
        authMethod: AuthMethod.privateKey,
        privateKey: _plainPem,
        passphrase: '',
      ),
    );

    expect(identities, hasLength(1));
  });

  test('key auth with no key configured resolves nothing', () async {
    expect(
      await resolveIdentities(
        profileFixture(authMethod: AuthMethod.privateKey),
      ),
      isNull,
    );
  });

  test('password auth resolves no identities at all', () async {
    expect(
      await resolveIdentities(
        profileFixture(authMethod: AuthMethod.password, password: 'pw'),
      ),
      isNull,
    );
  });
}

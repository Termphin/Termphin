import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

Future<List<Map<String, dynamic>>> storedKeys() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList('ssh_keys_v1') ?? const [])
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .toList();
}

void main() {
  late SshKeyStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = SshKeyStorage(cipher: cipherFixture());
  });

  test('saves, loads, and finds keys', () async {
    final keys = [sshKeyFixture(id: 'first'), sshKeyFixture(id: 'second')];

    await storage.saveKeys(keys);

    expect((await storage.loadKeys()).map((key) => key.id), [
      'first',
      'second',
    ]);
    expect((await storage.getKey('second'))?.id, 'second');
    expect(await storage.getKey('missing'), isNull);
  });

  test('generates and persists an Ed25519 key', () async {
    final key = await storage.generateEd25519('Phone', group: 'General');

    expect(key.keyType, SshKeyType.ed25519);
    expect(key.privateKeyPem, contains('PRIVATE KEY'));
    expect(key.publicKeyOpenSSH, startsWith('ssh-ed25519 '));
    expect((await storage.loadKeys()).single.id, key.id);
  });

  test('generates and persists an RSA 2048 key', () async {
    final key = await storage.generateRsa('Legacy', 2048, group: 'General');

    expect(key.keyType, SshKeyType.rsa2048);
    expect(key.privateKeyPem, contains('PRIVATE KEY'));
    expect(key.publicKeyOpenSSH, startsWith('ssh-rsa '));
  });

  test('imports a generated private key under a new name', () async {
    final generated = await storage.generateEd25519('Source', group: 'General');

    final imported = await storage.importFromPem(
      'Imported',
      generated.privateKeyPem,
      group: 'General',
    );

    expect(imported.name, 'Imported');
    expect(imported.keyType, SshKeyType.ed25519);
    expect(imported.publicKeyOpenSSH, contains(' Imported'));
    expect(await storage.loadKeys(), hasLength(2));
  });

  test('rejects invalid private key data', () async {
    expect(
      () => storage.importFromPem(
        'Broken',
        'not-a-private-key',
        group: 'General',
      ),
      throwsA(isA<Exception>()),
    );
  });

  group('passphrase-protected keys', () {
    test('import when given the passphrase', () async {
      final imported = await storage.importFromPem(
        'Locked',
        encryptedEd25519Pem,
        group: 'General',
        passphrase: encryptedEd25519Passphrase,
      );

      expect(imported.keyType, SshKeyType.ed25519);
      expect(
        imported.publicKeyOpenSSH,
        'ssh-ed25519 $encryptedEd25519PublicBlob Locked',
      );
      expect(imported.privateKeyPem, encryptedEd25519Pem);
      expect(await storage.loadKeys(), hasLength(1));
    });

    test('are refused, and say why, when no passphrase is given', () async {
      await expectLater(
        () => storage.importFromPem(
          'Locked',
          encryptedEd25519Pem,
          group: 'General',
        ),
        throwsA(
          isA<KeyImportException>().having(
            (e) => e.reason,
            'reason',
            KeyImportFailure.passphraseRequired,
          ),
        ),
      );
      expect(await storage.loadKeys(), isEmpty);
    });

    test('an empty passphrase counts as none', () async {
      await expectLater(
        () => storage.importFromPem(
          'Locked',
          encryptedEd25519Pem,
          group: 'General',
          passphrase: '',
        ),
        throwsA(
          isA<KeyImportException>().having(
            (e) => e.reason,
            'reason',
            KeyImportFailure.passphraseRequired,
          ),
        ),
      );
    });

    test('a wrong passphrase is told apart from a missing one', () async {
      await expectLater(
        () => storage.importFromPem(
          'Locked',
          encryptedEd25519Pem,
          group: 'General',
          passphrase: 'not-the-passphrase',
        ),
        throwsA(
          isA<KeyImportException>().having(
            (e) => e.reason,
            'reason',
            KeyImportFailure.wrongPassphrase,
          ),
        ),
      );
    });

    test('isEncryptedPem reads the key rather than guessing', () async {
      final plain = await storage.generateEd25519('Plain', group: 'General');

      expect(SshKeyStorage.isEncryptedPem(encryptedEd25519Pem), isTrue);
      expect(SshKeyStorage.isEncryptedPem(plain.privateKeyPem), isFalse);
      expect(SshKeyStorage.isEncryptedPem('not-a-private-key'), isFalse);
      expect(SshKeyStorage.isEncryptedPem(''), isFalse);
    });
  });

  test('skips corrupted persisted keys', () async {
    final valid = sshKeyFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_keys_v1': ['broken', valid.encode()],
    });

    expect((await storage.loadKeys()).map((key) => key.id), [valid.id]);
  });

  test('private keys never reach SharedPreferences in the clear', () async {
    await storage.saveKeys([sshKeyFixture(privateKeyPem: 'private-pem')]);

    final raw = (await storedKeys()).single;
    expect(raw['privateKeyPem'], startsWith('enc:v1:'));
    expect(jsonEncode(raw), isNot(contains('private-pem')));
    expect(raw['publicKeyOpenSSH'], startsWith('ssh-ed25519 '));
    expect((await storage.loadKeys()).single.privateKeyPem, 'private-pem');
  });

  test('keys written before encryption are read, then resealed', () async {
    SharedPreferences.setMockInitialValues({
      'ssh_keys_v1': [sshKeyFixture(privateKeyPem: 'private-pem').encode()],
    });

    expect((await storage.loadKeys()).single.privateKeyPem, 'private-pem');

    expect((await storedKeys()).single['privateKeyPem'], startsWith('enc:v1:'));
    expect((await storage.loadKeys()).single.privateKeyPem, 'private-pem');
  });

  test('a lost master key leaves the key listed but unusable', () async {
    await storage.saveKeys([sshKeyFixture(privateKeyPem: 'private-pem')]);

    final replaced = SshKeyStorage(cipher: cipherFixture(seed: 2));
    final loaded = (await replaced.loadKeys()).single;

    expect(loaded.privateKeyPem, isEmpty);
    expect(loaded.name, 'Laptop');
    expect(loaded.publicKeyOpenSSH, startsWith('ssh-ed25519 '));
  });
}

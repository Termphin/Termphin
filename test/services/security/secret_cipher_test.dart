import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/security/secret_cipher.dart';

import '../../support/fake_master_key_store.dart';

void main() {
  late FakeMasterKeyStore store;
  late SecretCipher cipher;

  setUp(() {
    store = FakeMasterKeyStore();
    cipher = cipherFixture(store: store);
  });

  test('seals and opens a value', () async {
    final sealed = await cipher.seal('hunter2', aad: 'profile-1/password');

    expect(cipher.isSealed(sealed), isTrue);
    expect(sealed, isNot(contains('hunter2')));
    expect(await cipher.open(sealed, aad: 'profile-1/password'), 'hunter2');
  });

  test('generates the master key once for concurrent first calls', () async {
    await Future.wait([
      cipher.seal('a', aad: 'x/password'),
      cipher.seal('b', aad: 'y/password'),
    ]);

    expect(store.writes, 1);
  });

  test('sealing the same value twice produces different ciphertext', () async {
    final first = await cipher.seal('hunter2', aad: 'profile-1/password');
    final second = await cipher.seal('hunter2', aad: 'profile-1/password');

    expect(first, isNot(second));
  });

  test('a record moved to another profile or field will not open', () async {
    final sealed = await cipher.seal('hunter2', aad: 'profile-1/password');

    expect(await cipher.open(sealed, aad: 'profile-2/password'), isNull);
    expect(await cipher.open(sealed, aad: 'profile-1/passphrase'), isNull);
  });

  test('tampered ciphertext will not open', () async {
    final sealed = await cipher.seal('hunter2', aad: 'profile-1/password');
    final tampered = sealed.replaceRange(
      sealed.length - 5,
      sealed.length - 4,
      sealed[sealed.length - 5] == 'A' ? 'B' : 'A',
    );

    expect(await cipher.open(tampered, aad: 'profile-1/password'), isNull);
  });

  test('truncated ciphertext will not open', () async {
    expect(await cipher.open('enc:v1:AAAA', aad: 'profile-1/password'), isNull);
  });

  test('values written before encryption pass through unchanged', () async {
    expect(cipher.isSealed('hunter2'), isFalse);
    expect(await cipher.open('hunter2', aad: 'profile-1/password'), 'hunter2');
  });

  test('a lost master key yields null rather than throwing', () async {
    final sealed = await cipher.seal('hunter2', aad: 'profile-1/password');
    final replaced = cipherFixture(seed: 2);

    expect(await replaced.open(sealed, aad: 'profile-1/password'), isNull);
  });

  test('an unreadable keystore does not stop the app starting', () async {
    final broken = cipherFixture(
      store: FakeMasterKeyStore('not base64 at all!!'),
      seed: 3,
    );

    final sealed = await broken.seal('hunter2', aad: 'profile-1/password');
    expect(await broken.open(sealed, aad: 'profile-1/password'), 'hunter2');
  });

  /// The keychain attributes the master key is written with, pinned because
  /// they cannot be changed on a device that already holds the entry: the item
  /// keeps whatever accessibility it was created with, so a later edit means
  /// deleting it and losing every sealed secret with it.
  group('master key keychain options', () {
    test('the key is kept off backups and off a transferred device', () {
      expect(
        kMasterKeyIOSOptions.accessibility,
        KeychainAccessibility.first_unlock_this_device,
      );
    });

    test('the key never syncs to iCloud', () {
      expect(kMasterKeyIOSOptions.synchronizable, isFalse);
    });
  });
}

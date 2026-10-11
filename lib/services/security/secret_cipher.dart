import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'aead.dart';

const _masterKeyEntry = 'termphin_master_key_v1';

/// How the master key is held in the iOS keychain.
///
/// `first_unlock_this_device` rather than the package's default of `unlocked`,
/// for the half of that name that is not about locking: a `ThisDeviceOnly`
/// item is left out of backups and out of a device-to-device transfer, so the
/// key that decrypts every stored password and private key cannot arrive on
/// hardware the user was not holding when they typed them. `first_unlock` over
/// `unlocked` because the key is read on the way into a connection, which a
/// screen that locked mid-transfer must not fail.
///
/// Changing this later is not free: an existing keychain item keeps the
/// accessibility it was written with, so a change needs the entry deleted and
/// rewritten, which on a device that has one means losing every sealed secret.
/// It is set now, before the iOS build ships, because that is when nobody has
/// one yet.
///
/// `synchronizable` is already false by default, which is what keeps this out
/// of iCloud Keychain; it is named here so a future edit has to decide about
/// it deliberately.
const kMasterKeyIOSOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
  synchronizable: false,
);

/// Where the master key lives. Abstracted so tests can supply an in-memory
/// double rather than driving the Android Keystore over a platform channel.
abstract class MasterKeyStore {
  Future<String?> read();
  Future<void> write(String value);
}

class KeystoreMasterKeyStore implements MasterKeyStore {
  const KeystoreMasterKeyStore([
    this._storage = const FlutterSecureStorage(iOptions: kMasterKeyIOSOptions),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _masterKeyEntry);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _masterKeyEntry, value: value);
}

/// Seals the credentials that [ProfileStorage] and [SshKeyStorage] persist.
///
/// One random 256-bit master key encrypts every secret; only the master key
/// itself is held by the platform keystore. Storing each secret in the
/// keystore directly would be simpler, but keystore material is device-bound
/// and cannot be exported, so a layout built on it could never leave the
/// device.
class SecretCipher {
  SecretCipher({MasterKeyStore? store, Random? random})
    : _store = store ?? const KeystoreMasterKeyStore(),
      _random = random;

  static final SecretCipher instance = SecretCipher();

  final MasterKeyStore _store;
  final Random? _random;

  Uint8List? _masterKey;

  /// Held only while the first load is in flight, so two concurrent callers
  /// cannot each generate a master key and have one silently win. Dropped once
  /// resolved: a future outlives the zone it was created in, and awaiting a
  /// stale one never resumes.
  Future<Uint8List>? _loadingMasterKey;

  bool isSealed(String value) => value.startsWith(sealPrefix);

  Future<Uint8List> masterKey() async {
    final cached = _masterKey;
    if (cached != null) return cached;
    try {
      return _masterKey = await (_loadingMasterKey ??= _loadOrCreateKey());
    } finally {
      _loadingMasterKey = null;
    }
  }

  Future<String> seal(String plaintext, {required String aad}) async =>
      sealBytes(
        await masterKey(),
        utf8Bytes(plaintext),
        aad: aad,
        random: _random,
      );

  /// Returns [value] unchanged when it predates encryption, so callers can
  /// hand over whatever is on disk.
  ///
  /// Null means the value could not be opened: either the master key is gone
  /// (keystore entries do not survive a device transfer, and some vendors drop
  /// them when the screen lock changes) or the record was tampered with.
  /// Callers keep the surrounding record and ask the user for the secret
  /// again rather than treating the whole entry as lost.
  Future<String?> open(String value, {required String aad}) async {
    if (!isSealed(value)) return value;
    final opened = openBytes(await masterKey(), value, aad: aad);
    if (opened == null) return null;
    try {
      return utf8.decode(opened);
    } catch (_) {
      return null;
    }
  }

  /// Reads the stored master key, or generates and stores a fresh one.
  ///
  /// A keystore that cannot be read is indistinguishable from a missing key:
  /// either way the old ciphertext is unrecoverable, and refusing to start
  /// would strand the user with an app that never works again.
  Future<Uint8List> _loadOrCreateKey() async {
    try {
      final stored = await _store.read();
      if (stored != null) {
        final decoded = base64Decode(stored);
        if (decoded.length == 32) return decoded;
      }
    } catch (error) {
      debugPrint('[SecretCipher] Unable to read the master key: $error');
    }
    final fresh = randomBytes(32, _random);
    await _store.write(base64Encode(fresh));
    return fresh;
  }
}

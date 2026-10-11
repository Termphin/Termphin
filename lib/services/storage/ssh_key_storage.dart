import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/ssh_key.dart';
import '../security/secret_cipher.dart';
import 'write_queue.dart';

const _kSshKeysPrefsKey = 'ssh_keys_v1';
const _uuid = Uuid();

/// The only field worth sealing - the public half and the metadata stay
/// readable so the key manager can list keys without touching the keystore.
const _secretField = 'privateKeyPem';

/// Why importing a private key failed, in terms the UI can act on.
enum KeyImportFailure { passphraseRequired, wrongPassphrase }

class KeyImportException implements Exception {
  KeyImportException(this.reason, this.message);

  final KeyImportFailure reason;

  /// dartssh2's own wording, kept for the generic error path.
  final String message;

  @override
  String toString() => message;
}

class SshKeyStorage {
  SshKeyStorage({SecretCipher? cipher})
    : _cipher = cipher ?? SecretCipher.instance;

  final SecretCipher _cipher;

  /// See [ProfileStorage] - shared across instances because the thing being
  /// serialised is the SharedPreferences key, not the object holding it.
  static final WriteQueue _writes = WriteQueue();

  /// Loads stored keys, resealing any entry written before encryption
  /// shipped - that migration needs no separate step, since it happens on
  /// the first read.
  Future<List<SshKey>> loadKeys() async {
    final (keys, sawPlaintext) = await _read();
    if (sawPlaintext) await saveKeys(keys);
    return keys;
  }

  /// Decodes what is on disk. Kept separate from [loadKeys] so [saveKeys] can
  /// look at the stored records without re-entering the migration that calls
  /// it.
  ///
  /// A key whose PEM cannot be opened is useless but still worth listing, so
  /// the user can see what to re-import instead of it silently vanishing. An
  /// entry that fails to decode at all is skipped instead, so the rest of
  /// the keys are still available.
  Future<(List<SshKey>, bool)> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_kSshKeysPrefsKey) ?? [];
    final keys = <SshKey>[];
    var sawPlaintext = false;
    for (final rawKey in rawList) {
      try {
        final json = jsonDecode(rawKey) as Map<String, dynamic>;
        final id = json['id'] as String;
        final pem = json[_secretField] as String?;
        if (pem != null) {
          if (!_cipher.isSealed(pem)) sawPlaintext = true;
          json[_secretField] =
              await _cipher.open(pem, aad: '$id/$_secretField') ?? '';
        }
        keys.add(SshKey.fromJson(json));
      } catch (_) {}
    }
    return (keys, sawPlaintext);
  }

  Future<void> saveKeys(List<SshKey> keys) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = <String>[];
    for (final key in keys) {
      final json = key.toJson();
      final pem = json[_secretField] as String?;
      if (pem != null && pem.isNotEmpty) {
        json[_secretField] = await _cipher.seal(
          pem,
          aad: '${key.id}/$_secretField',
        );
      }
      encoded.add(jsonEncode(json));
    }
    await prefs.setStringList(_kSshKeysPrefsKey, encoded);
  }

  Future<void> deleteKey(String keyId) => _writes.run(() async {
    final keys = await loadKeys();
    keys.removeWhere((key) => key.id == keyId);
    await saveKeys(keys);
  });

  Future<void> updateKey(SshKey key) => _writes.run(() async {
    final keys = await loadKeys();
    final index = keys.indexWhere((k) => k.id == key.id);
    if (index == -1) {
      throw StateError('Key not found.');
    }
    keys[index] = key;
    await saveKeys(keys);
  });

  Future<SshKey?> getKey(String id) async {
    final keys = await loadKeys();
    try {
      return keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<SshKey> generateEd25519(String name, {required String group}) async {
    final signingKey = nacl.SigningKey.generate();
    final pubBytes = Uint8List.fromList(signingKey.verifyKey.asTypedList);
    final privBytes = Uint8List.fromList(signingKey.asTypedList);

    final keyPair = OpenSSHEd25519KeyPair(pubBytes, privBytes, name);
    final pem = keyPair.toPem();
    final publicKeyStr = _buildEd25519PublicKey(pubBytes, name);

    final key = SshKey(
      id: _uuid.v4(),
      name: name,
      keyType: SshKeyType.ed25519,
      privateKeyPem: pem,
      publicKeyOpenSSH: publicKeyStr,
      createdAt: DateTime.now(),
      group: group,
    );

    return _addAndSave(key);
  }

  Future<SshKey> generateRsa(
    String name,
    int bits, {
    required String group,
  }) async {
    final rsaPair = await compute(_generateRsaKeyPair, bits);
    final n = rsaPair.priv.modulus!;
    final e = rsaPair.pub.publicExponent!;
    final d = rsaPair.priv.privateExponent!;
    final p = rsaPair.priv.p!;
    final q = rsaPair.priv.q!;
    final iqmp = q.modInverse(p);

    final keyPair = OpenSSHRsaKeyPair(n, e, d, iqmp, p, q, name);
    final pem = keyPair.toPem();
    final pubKeyEncoded = keyPair.toPublicKey().encode();
    final publicKeyStr = 'ssh-rsa ${base64.encode(pubKeyEncoded)} $name';

    final keyType = bits == 4096 ? SshKeyType.rsa4096 : SshKeyType.rsa2048;

    final key = SshKey(
      id: _uuid.v4(),
      name: name,
      keyType: keyType,
      privateKeyPem: pem,
      publicKeyOpenSSH: publicKeyStr,
      createdAt: DateTime.now(),
      group: group,
    );

    return _addAndSave(key);
  }

  /// Whether [pem] is passphrase-protected, and so cannot be read without one.
  ///
  /// Text this cannot parse at all counts as not encrypted: the import is what
  /// reports a malformed key, and guessing here would ask for a passphrase
  /// that no amount of typing makes right.
  static bool isEncryptedPem(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem);
    } catch (_) {
      return false;
    }
  }

  /// [passphrase] unlocks an encrypted key long enough to read its public half.
  /// It is deliberately not stored: the PEM is kept exactly as the user gave
  /// it, still encrypted, and the profile that uses the key carries the
  /// passphrase for connecting.
  ///
  /// A decrypt failure is classified here, where the difference between no
  /// passphrase and the wrong one is still known - dartssh2 only says
  /// "Private key is encrypted" or "Invalid passphrase" in prose, and
  /// matching on that at the call site is what this avoids.
  Future<SshKey> importFromPem(
    String name,
    String pem, {
    required String group,
    String? passphrase,
  }) async {
    final supplied = passphrase == null || passphrase.isEmpty
        ? null
        : passphrase;
    final List<SSHKeyPair> pairs;
    try {
      pairs = SSHKeyPair.fromPem(pem, supplied);
    } on SSHKeyDecryptError catch (error) {
      throw KeyImportException(
        supplied == null
            ? KeyImportFailure.passphraseRequired
            : KeyImportFailure.wrongPassphrase,
        '$error',
      );
    }
    if (pairs.isEmpty) {
      throw Exception('No keys found in PEM data.');
    }
    final pair = pairs.first;
    final pubKeyBytes = pair.toPublicKey().encode();
    final keyTypeName = pair.name;
    final publicKeyStr = '$keyTypeName ${base64.encode(pubKeyBytes)} $name';

    final keyType = keyTypeName == 'ssh-ed25519'
        ? SshKeyType.ed25519
        : SshKeyType.rsa2048;

    final key = SshKey(
      id: _uuid.v4(),
      name: name,
      keyType: keyType,
      privateKeyPem: pem,
      publicKeyOpenSSH: publicKeyStr,
      createdAt: DateTime.now(),
      group: group,
    );

    return _addAndSave(key);
  }

  Future<SshKey> _addAndSave(SshKey key) => _writes.run(() async {
    final keys = await loadKeys();
    keys.add(key);
    await saveKeys(keys);
    return key;
  });

  String _buildEd25519PublicKey(Uint8List pubKey32, String comment) {
    final builder = BytesBuilder();

    void writeField(List<int> bytes) {
      final len = bytes.length;
      builder.add([
        (len >> 24) & 0xff,
        (len >> 16) & 0xff,
        (len >> 8) & 0xff,
        len & 0xff,
      ]);
      builder.add(bytes);
    }

    final typeBytes = utf8.encode('ssh-ed25519');
    writeField(typeBytes);
    writeField(pubKey32);

    return 'ssh-ed25519 ${base64.encode(builder.toBytes())} $comment';
  }
}

class _RsaKeyPairData {
  final RSAPublicKey pub;
  final RSAPrivateKey priv;
  _RsaKeyPairData(this.pub, this.priv);
}

_RsaKeyPairData _generateRsaKeyPair(int bits) {
  final secureRandom = FortunaRandom();
  final seedSource = Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

  final keyGen = RSAKeyGenerator();
  keyGen.init(
    ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.parse('65537'), bits, 64),
      secureRandom,
    ),
  );

  final pair = keyGen.generateKeyPair();
  return _RsaKeyPairData(pair.publicKey, pair.privateKey);
}

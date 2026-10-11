import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../security/aead.dart';

/// Marks a file as ours. Without it any JSON object with no recognised
/// section reads as an empty backup, which imports "successfully" and does
/// nothing.
const kBackupFormat = 'termphin-backup';

/// Bumped whenever a section is added. Readers accept anything up to this and
/// refuse what is newer rather than importing the parts they happen to
/// recognise.
const kBackupVersion = 4;
const kMinBackupVersion = 1;

const _kdfName = 'pbkdf2-hmac-sha256';

/// OWASP's 2023 floor for PBKDF2-HMAC-SHA256. Roughly 0.6s on a laptop and a
/// couple of seconds on a phone, which is why the derivation runs off the UI
/// isolate.
const _kdfIterations = 210000;
const _saltBytes = 16;
const _keyBytes = 32;

/// Binds the ciphertext to this envelope's purpose - see [sealBytes].
const _aad = 'termphin-backup';

/// Why a file could not be read as a backup.
enum BackupProblem {
  /// Not JSON, or JSON that carries no backup marker and no known section.
  notABackup,

  /// Written by a newer build than this one.
  unsupportedVersion,

  /// Sealed with a passphrase that has not been supplied yet.
  passphraseRequired,

  /// Sealed, and the supplied passphrase does not open it.
  wrongPassphrase,
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupFormatException(${problem.name})';
}

/// True for an envelope written by [encryptBackup]. Callers use it to know a
/// passphrase has to be asked for before anything can be previewed.
bool isEncryptedBackup(String raw) {
  final envelope = _decodeObject(raw);
  return envelope != null && envelope['encrypted'] == true;
}

/// Wraps [plaintextJson] in a passphrase-sealed envelope.
///
/// The envelope's own header stays readable so a file can be recognised, and
/// its version reported, without the passphrase.
Future<String> encryptBackup(String plaintextJson, String passphrase) async {
  final salt = randomBytes(_saltBytes);
  final key = await _deriveKey(passphrase, salt, _kdfIterations);
  return const JsonEncoder.withIndent('  ').convert({
    'format': kBackupFormat,
    'version': kBackupVersion,
    'encrypted': true,
    'kdf': {
      'algorithm': _kdfName,
      'iterations': _kdfIterations,
      'salt': base64Encode(salt),
    },
    'payload': sealBytes(key, utf8Bytes(plaintextJson), aad: _aad),
  });
}

/// The plaintext JSON inside [raw].
///
/// Throws [BackupFormatException] with [BackupProblem.wrongPassphrase] when
/// the seal will not open - which is also what a tampered file looks like,
/// since neither can be told from the other and both mean the same thing to
/// the user.
Future<String> decryptBackup(String raw, String passphrase) async {
  final envelope = _decodeObject(raw);
  if (envelope == null || envelope['encrypted'] != true) {
    throw const BackupFormatException(BackupProblem.notABackup);
  }
  final kdf = envelope['kdf'];
  final payload = envelope['payload'];
  if (kdf is! Map || payload is! String) {
    throw const BackupFormatException(BackupProblem.notABackup);
  }
  if (kdf['algorithm'] != _kdfName) {
    throw const BackupFormatException(BackupProblem.unsupportedVersion);
  }
  final iterations = (kdf['iterations'] as num?)?.toInt();
  final saltRaw = kdf['salt'];
  if (iterations == null || iterations <= 0 || saltRaw is! String) {
    throw const BackupFormatException(BackupProblem.notABackup);
  }

  final Uint8List salt;
  try {
    salt = base64Decode(saltRaw);
  } catch (_) {
    throw const BackupFormatException(BackupProblem.notABackup);
  }

  final key = await _deriveKey(passphrase, salt, iterations);
  final opened = openBytes(key, payload, aad: _aad);
  if (opened == null) {
    throw const BackupFormatException(BackupProblem.wrongPassphrase);
  }
  try {
    return utf8.decode(opened);
  } catch (_) {
    throw const BackupFormatException(BackupProblem.wrongPassphrase);
  }
}

Map<String, dynamic>? _decodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Off the UI isolate: at [_kdfIterations] this is seconds of solid CPU on a
/// phone, and doing it inline drops every frame for the duration.
Future<Uint8List> _deriveKey(
  String passphrase,
  Uint8List salt,
  int iterations,
) {
  return Isolate.run(() => derivePassphraseKey(passphrase, salt, iterations));
}

/// Exposed for tests, which have no reason to pay for an isolate hop.
Uint8List derivePassphraseKey(
  String passphrase,
  Uint8List salt,
  int iterations,
) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, _keyBytes));
  return derivator.process(utf8Bytes(passphrase));
}

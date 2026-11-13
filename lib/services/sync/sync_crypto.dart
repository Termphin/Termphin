import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../backup/backup_crypto.dart';
import '../security/aead.dart';

/// PBKDF2 rounds for the sync passphrase: the backup's, so a phone takes the
/// same few seconds once per device rather than per sync.
const kSyncKdfIterations = 210000;

/// What the key is checked against: sealed with it when sync is set up, so
/// another device can tell a wrong passphrase from damaged data before it
/// touches anything.
const _checkPlaintext = 'termphin-sync-check';

/// The key everything synced is sealed with, derived from the sync
/// passphrase on the device. Nothing that leaves the device can open a
/// record without it - not Firebase, not us.
class SyncKey {
  SyncKey(this.bytes) : assert(bytes.length == 32);

  final Uint8List bytes;

  /// Derives the key from [passphrase] off the UI isolate.
  static Future<SyncKey> derive(
    String passphrase,
    Uint8List salt, {
    int iterations = kSyncKdfIterations,
  }) async => SyncKey(
    await Isolate.run(() => derivePassphraseKey(passphrase, salt, iterations)),
  );

  /// The document a record lives in. A keyed hash of what the record is, so
  /// the store sees neither its kind nor its id - only that there are some
  /// number of records.
  String documentId(String kind, String id) {
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(bytes));
    final digest = mac.process(utf8Bytes('record/$kind/$id'));
    return digest
        .take(20)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Seals [payload] for document [documentId] of user [uid]. The AAD ties it
  /// to both, so a record cannot be moved to another document or account.
  String seal(
    Map<String, Object?> payload, {
    required String uid,
    required String documentId,
  }) => sealBytes(
    bytes,
    utf8Bytes(jsonEncode(payload)),
    aad: _aad(uid, documentId),
  );

  /// The payload sealed in [ciphertext], or null if this key did not seal
  /// it for this document and account, or it was tampered with.
  Map<String, Object?>? open(
    String ciphertext, {
    required String uid,
    required String documentId,
  }) {
    final plain = openBytes(bytes, ciphertext, aad: _aad(uid, documentId));
    if (plain == null) return null;
    try {
      return (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  String sealCheck(String uid) => sealBytes(
    bytes,
    utf8Bytes(_checkPlaintext),
    aad: 'termphin-sync/$uid/check',
  );

  bool opensCheck(String uid, String check) {
    final plain = openBytes(bytes, check, aad: 'termphin-sync/$uid/check');
    return plain != null && utf8.decode(plain) == _checkPlaintext;
  }

  static String _aad(String uid, String documentId) =>
      'termphin-sync/$uid/$documentId';
}

/// A stable digest of [value]'s JSON, keys sorted, for telling whether a
/// record changed since it was last synced.
String contentHash(Object? value) {
  final digest = SHA256Digest().process(utf8Bytes(_canonical(value)));
  return base64Url.encode(digest);
}

String _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonical(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

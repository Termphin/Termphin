import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Prefix marking a value as sealed. Anything without it predates encryption
/// and is treated as plaintext, which is what makes the storage migrations
/// self-healing. Bumping the version is also how key rotation would land.
const sealPrefix = 'enc:v1:';

const _nonceBytes = 12;
const _macBits = 128;

final _random = Random.secure();

Uint8List randomBytes(int length, [Random? random]) {
  final source = random ?? _random;
  return Uint8List.fromList(
    List<int>.generate(length, (_) => source.nextInt(256)),
  );
}

/// AES-256-GCM, nonce prepended, base64 behind [sealPrefix].
///
/// [aad] binds the ciphertext to what it belongs to. Without it, anyone able
/// to write to the sync store could move one record's ciphertext onto another
/// record: the bytes would be untouched and the tag would still verify.
String sealBytes(
  Uint8List key,
  Uint8List plaintext, {
  required String aad,
  Random? random,
}) {
  final nonce = randomBytes(_nonceBytes, random);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), _macBits, nonce, utf8Bytes(aad)),
    );
  return '$sealPrefix${base64Encode([...nonce, ...cipher.process(plaintext)])}';
}

/// Null when the value cannot be opened: wrong key, wrong [aad], or tampering.
Uint8List? openBytes(Uint8List key, String sealed, {required String aad}) {
  if (!sealed.startsWith(sealPrefix)) return null;
  try {
    final raw = base64Decode(sealed.substring(sealPrefix.length));
    if (raw.length <= _nonceBytes) return null;
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          _macBits,
          Uint8List.sublistView(raw, 0, _nonceBytes),
          utf8Bytes(aad),
        ),
      );
    return cipher.process(Uint8List.sublistView(raw, _nonceBytes));
  } catch (error) {
    debugPrint('[aead] Unable to open a sealed value: $error');
    return null;
  }
}

Uint8List utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));

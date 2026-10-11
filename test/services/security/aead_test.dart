import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/security/aead.dart';

Uint8List _key(int seed) => randomBytes(32, Random(seed));

void main() {
  final key = _key(1);
  final otherKey = _key(2);

  group('sealBytes / openBytes', () {
    test('round-trips under the same key and aad', () {
      final plaintext = utf8Bytes('hunter2');
      final sealed = sealBytes(key, plaintext, aad: 'profile:7');
      expect(openBytes(key, sealed, aad: 'profile:7'), plaintext);
    });

    test('marks the value with the seal prefix and nothing readable', () {
      final sealed = sealBytes(key, utf8Bytes('hunter2'), aad: 'a');
      expect(sealed, startsWith(sealPrefix));
      expect(sealed, isNot(contains('hunter2')));
      expect(base64Decode(sealed.substring(sealPrefix.length)), isNotEmpty);
    });

    test('refuses the wrong key', () {
      final sealed = sealBytes(key, utf8Bytes('secret'), aad: 'a');
      expect(openBytes(otherKey, sealed, aad: 'a'), isNull);
    });

    test('refuses the wrong aad, which is what stops a record swap', () {
      final sealed = sealBytes(key, utf8Bytes('secret'), aad: 'profile:7');
      expect(openBytes(key, sealed, aad: 'profile:8'), isNull);
      expect(openBytes(key, sealed, aad: ''), isNull);
    });

    test('refuses a tampered ciphertext', () {
      final sealed = sealBytes(key, utf8Bytes('secret'), aad: 'a');
      final raw = base64Decode(sealed.substring(sealPrefix.length));
      raw[raw.length - 1] ^= 0x01;
      expect(
        openBytes(key, '$sealPrefix${base64Encode(raw)}', aad: 'a'),
        isNull,
      );
    });

    test('refuses a tampered nonce', () {
      final sealed = sealBytes(key, utf8Bytes('secret'), aad: 'a');
      final raw = base64Decode(sealed.substring(sealPrefix.length));
      raw[0] ^= 0x01;
      expect(
        openBytes(key, '$sealPrefix${base64Encode(raw)}', aad: 'a'),
        isNull,
      );
    });

    test('uses a fresh nonce per call, so equal plaintexts differ', () {
      final plaintext = utf8Bytes('same');
      final first = sealBytes(key, plaintext, aad: 'a');
      final second = sealBytes(key, plaintext, aad: 'a');
      expect(first, isNot(second));
      expect(openBytes(key, first, aad: 'a'), plaintext);
      expect(openBytes(key, second, aad: 'a'), plaintext);
    });

    test('round-trips an empty value and arbitrary bytes', () {
      final empty = Uint8List(0);
      expect(openBytes(key, sealBytes(key, empty, aad: 'a'), aad: 'a'), empty);

      final binary = Uint8List.fromList(List.generate(256, (i) => i));
      expect(
        openBytes(key, sealBytes(key, binary, aad: 'a'), aad: 'a'),
        binary,
      );
    });

    test('round-trips text outside ASCII', () {
      final text = utf8Bytes('zażółć gęślą jaźń 日本語 🐬');
      expect(openBytes(key, sealBytes(key, text, aad: 'a'), aad: 'a'), text);
    });
  });

  group('openBytes on values it should not touch', () {
    test('treats an unprefixed value as plaintext by returning null', () {
      expect(openBytes(key, 'plain-password', aad: 'a'), isNull);
      expect(openBytes(key, '', aad: 'a'), isNull);
    });

    test('rejects a prefixed value too short to hold a nonce', () {
      expect(
        openBytes(key, '$sealPrefix${base64Encode(Uint8List(12))}', aad: 'a'),
        isNull,
      );
      expect(openBytes(key, '${sealPrefix}not-base64!!', aad: 'a'), isNull);
    });
  });

  group('randomBytes', () {
    test('returns the requested length in range', () {
      final bytes = randomBytes(32);
      expect(bytes, hasLength(32));
      expect(bytes.every((b) => b >= 0 && b <= 255), isTrue);
      expect(randomBytes(0), isEmpty);
    });

    test('is deterministic when handed a seeded source', () {
      expect(randomBytes(16, Random(42)), randomBytes(16, Random(42)));
    });

    test('does not repeat itself from the secure source', () {
      expect(randomBytes(32), isNot(randomBytes(32)));
    });
  });
}

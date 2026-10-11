import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// The helpers ship gzipped because App Store validation refuses a Mach-O
/// anywhere in the app bundle. That makes the shipped file and the digest in
/// the manifest two different things, which is exactly the kind of pairing
/// that rots: someone drops in a new binary, forgets to compress it, and the
/// upload to a server fails at the SHA-256 check with no clue why.
void main() {
  const directory = 'assets/termphin-agent';

  late Map<String, String> manifest;

  setUpAll(() {
    manifest = {
      for (final line in File(
        '$directory/manifest.properties',
      ).readAsLinesSync())
        if (line.contains('=')) ...{
          line.split('=').first.trim(): line
              .split('=')
              .sublist(1)
              .join('=')
              .trim(),
        },
    };
  });

  test('every bundled helper is gzipped', () {
    final files = manifest.entries
        .where((e) => e.key.endsWith('.file'))
        .map((e) => e.value)
        .toList();

    expect(files, isNotEmpty);
    for (final file in files) {
      expect(file, endsWith('.gz'), reason: '$file is not compressed');
      expect(File('$directory/$file').existsSync(), isTrue, reason: file);
    }
  });

  test('each archive unpacks to the helper the manifest names', () {
    for (final entry in manifest.entries) {
      if (!entry.key.endsWith('.file')) continue;
      final key = entry.key.substring(0, entry.key.length - '.file'.length);
      final expected = manifest['$key.sha256'];
      expect(expected, isNotNull, reason: 'no digest for $key');

      final packed = File('$directory/${entry.value}').readAsBytesSync();
      final unpacked = gzip.decode(packed);
      final digest = SHA256Digest()
          .process(Uint8List.fromList(unpacked))
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      expect(digest, expected, reason: 'digest mismatch for $key');
    }
  });
}

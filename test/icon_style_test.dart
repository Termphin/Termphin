import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Check, plus and close glyphs ship in the regular Phosphor weight only -
/// the filled variants read as heavy blobs at the sizes the app uses them at.
/// The prefixes cover every variant: `check` also catches `checkCircle`,
/// `checkSquare` and `checks`, `plus` catches `plusCircle` and `plusSquare`.
///
/// The bare `x` is matched on its own rather than as a prefix, because
/// `xCircle` is a badge rather than a control - a filled one is what marks a
/// failed run and an error toast.
void main() {
  test('no filled check, plus or close icons in lib/', () {
    final forbidden = [
      RegExp(r'PhosphorIconsFill\.check'),
      RegExp(r'PhosphorIconsFill\.plus'),
      RegExp(r'PhosphorIconsFill\.x(?![A-Za-z])'),
    ];

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      for (final pattern in forbidden) {
        final match = pattern.firstMatch(content);
        if (match != null) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

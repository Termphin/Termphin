import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spacing, type, icon sizes, corners and colours come from
/// `lib/theme/theme.dart` and nowhere else.
///
/// The app had grown about seven hundred hand-typed paddings and a few dozen
/// private copies of the same card, chip and pill, each a pixel or a shade
/// away from the others. The tokens and the kit in `lib/widgets/ui/` are the
/// one source now; this keeps a literal from creeping back in. A value that
/// is missing from a scale is added to the scale, not typed at the call site.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/theme/'))
      .where((f) => !f.path.startsWith('lib/i18n/'))
      .toList();

  final nonZeroNumber = RegExp(
    r'(?<![\w.])(?<![-+/*<>=]\s*)(?!0(?:\.0+)?\b)\d+(?:\.\d+)?\b',
  );

  List<String> scan(
    void Function(String source, void Function(int, String) hit) check,
  ) {
    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      check(source, (offset, snippet) {
        final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
        offenders.add('${file.path}:$line: $snippet');
      });
    }
    return offenders;
  }

  Iterable<(int, String)> calls(String source, RegExp opener) sync* {
    for (final match in opener.allMatches(source)) {
      var depth = 1;
      var i = match.end;
      while (i < source.length && depth > 0) {
        final c = source[i];
        if (c == '(') depth++;
        if (c == ')') depth--;
        i++;
      }
      yield (match.start, source.substring(match.end, i - 1));
    }
  }

  test('paddings use the spacing scale', () {
    final offenders = scan((source, hit) {
      for (final (offset, args) in calls(
        source,
        RegExp(r'EdgeInsets(?:Directional)?\.\w+\('),
      )) {
        if (nonZeroNumber.hasMatch(args)) {
          hit(offset, args.replaceAll(RegExp(r'\s+'), ' '));
        }
      }
    });
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('spacers use the spacing scale', () {
    final spacer = RegExp(
      r'SizedBox\(\s*(?:height|width):\s*(\d+(?:\.\d+)?)\s*,?\s*\)',
    );
    final offenders = scan((source, hit) {
      for (final m in spacer.allMatches(source)) {
        if (double.parse(m.group(1)!) != 0) hit(m.start, m.group(0)!);
      }
    });
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('font sizes use the type scale', () {
    final pattern = RegExp(r'fontSize:\s*\d');
    final offenders = scan((source, hit) {
      for (final m in pattern.allMatches(source)) {
        hit(m.start, m.group(0)!);
      }
    });
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('icon sizes use the icon scale', () {
    final iconSize = RegExp(r'iconSize:\s*\d');
    final sizeArg = RegExp(r'(?<![\w.])size:\s*\d');
    final offenders = scan((source, hit) {
      for (final m in iconSize.allMatches(source)) {
        hit(m.start, m.group(0)!);
      }
      for (final (offset, args) in calls(source, RegExp(r'\bIcon\('))) {
        final m = sizeArg.firstMatch(args);
        if (m != null) hit(offset, m.group(0)!);
      }
    });
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('corners use the radius scale', () {
    final pattern = RegExp(
      r'\b(?:BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?)',
    );
    final offenders = scan((source, hit) {
      for (final m in pattern.allMatches(source)) {
        if (double.parse(m.group(1)!) != 0) hit(m.start, m.group(0)!);
      }
    });
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('colours come from the palette', () {
    const allowed = {
      'lib/screens/sftp/sftp_image_preview_screen.dart': {'Colors.black'},
    };
    final pattern = RegExp(r'\bColors\.\w+|\bColor\(0x[0-9A-Fa-f]+\)');
    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final m in pattern.allMatches(source)) {
        if (allowed[file.path]?.contains(m.group(0)) ?? false) continue;
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        offenders.add('${file.path}:$line: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

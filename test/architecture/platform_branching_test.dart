import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens and widgets ask what the system can do (`platformHas`) or whether
/// the user is on a desktop (`isDesktopPlatform`) - never which platform it is
/// spelled out by hand, and never through the raw Flutter primitives that the
/// app's adaptive helpers exist to wrap. A rule that lives only in a document
/// is broken by the first change made in a hurry.
void main() {
  const scanned = ['lib/screens', 'lib/widgets'];

  /// Each banned pattern with the files that legitimately own it.
  ///
  /// `terminal_pane.dart` hands the platform to terminal_view, which decides
  /// its own key encoding from it. A page is opened with `pushAppPage`, a form
  /// with `pushAppForm`, a work window with `pushAppWindow` - each picks the
  /// desktop's presentation - so a `MaterialPageRoute` belongs only to those
  /// helpers, to the manual (over a sheet on a phone, a window on a desktop)
  /// and to the share screen, which runs in its own engine opened by the
  /// system's share sheet on a phone and has no desktop to adapt to.
  final banned = <RegExp, Set<String>>{
    RegExp(r'\bdefaultTargetPlatform\b'): {
      'lib/widgets/terminal/terminal_pane.dart',
    },
    RegExp(r'\bPlatform\.is[A-Z]'): {},
    RegExp(r'\bshowModalBottomSheet\b'): {'lib/widgets/ui/app_sheet.dart'},
    RegExp(r'fullscreenDialog:\s*true'): {'lib/widgets/ui/app_sheet.dart'},
    RegExp(r'\bMaterialPageRoute\b'): {
      'lib/widgets/ui/app_sheet.dart',
      'lib/widgets/ui/section_navigator.dart',
      'lib/widgets/ui/manual_link.dart',
      'lib/screens/share/share_screen.dart',
      'lib/widgets/terminal/terminal_scheme_theme.dart',
    },
  };

  test('platform is read through the adaptive helpers only', () {
    final offences = <String>[];
    for (final root in scanned) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          for (final MapEntry(key: pattern, value: allowed) in banned.entries) {
            if (allowed.contains(path)) continue;
            if (pattern.hasMatch(line)) {
              offences.add('$path:${i + 1}: ${pattern.pattern}');
            }
          }
        }
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}

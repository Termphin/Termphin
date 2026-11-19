import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

Intent? _intentFor(SingleActivator activator) {
  for (final entry in desktopTerminalShortcuts().entries) {
    final key = entry.key;
    if (key is SingleActivator &&
        key.trigger == activator.trigger &&
        key.control == activator.control &&
        key.shift == activator.shift &&
        key.meta == activator.meta) {
      return entry.value;
    }
  }
  return null;
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('off a Mac Ctrl+C copies only a selection, Ctrl+V pastes, and plain '
      'Ctrl+A stays the shell\'s', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    expect(
      _intentFor(const SingleActivator(LogicalKeyboardKey.keyC, control: true)),
      isA<CopyIfSelectedIntent>(),
    );
    expect(
      _intentFor(const SingleActivator(LogicalKeyboardKey.keyV, control: true)),
      isA<PasteTextIntent>(),
    );
    expect(
      _intentFor(const SingleActivator(LogicalKeyboardKey.keyA, control: true)),
      isNull,
    );
    expect(
      _intentFor(
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ),
      ),
      isA<CopySelectionTextIntent>(),
    );
  });

  test('a Mac copies and pastes on Cmd and leaves Ctrl to the shell', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    expect(
      _intentFor(const SingleActivator(LogicalKeyboardKey.keyC, meta: true)),
      isA<CopySelectionTextIntent>(),
    );
    expect(
      _intentFor(const SingleActivator(LogicalKeyboardKey.keyV, meta: true)),
      isA<PasteTextIntent>(),
    );
    expect(
      _intentFor(const SingleActivator(LogicalKeyboardKey.keyC, control: true)),
      isNull,
    );
  });
}

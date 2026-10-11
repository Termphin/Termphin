import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/app/app_commands.dart';

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// Installs the handler here, not in setUp: the platform variant is only in
/// force from inside the test body, and the handler is a desktop's only.
Future<void> _pumpApp(WidgetTester tester, {Widget? body}) async {
  AppCommands.instance.install();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [AppCommands.instance.modalObserver],
      home: Scaffold(body: body ?? const SizedBox()),
    ),
  );
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  final unregister = <VoidCallback>[];

  tearDown(() {
    for (final u in unregister) {
      u();
    }
    unregister.clear();
    AppCommands.instance.uninstall();
  });

  testWidgets('a shortcut runs its command before the focused widget sees '
      'the key', (tester) async {
    var ran = 0;
    unregister.add(
      AppCommands.instance.register(AppCommand.newSession, (_) {
        ran++;
        return true;
      }),
    );
    final field = TextEditingController();
    await _pumpApp(tester, body: TextField(controller: field, autofocus: true));
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyT, control: true, shift: true);

    expect(ran, 1);
    expect(field.text, isEmpty);
  }, variant: _linux);

  testWidgets('plain Ctrl keys are left to the shell', (tester) async {
    var ran = 0;
    unregister.add(
      AppCommands.instance.register(AppCommand.newSession, (_) {
        ran++;
        return true;
      }),
    );
    await _pumpApp(tester);

    await _press(tester, LogicalKeyboardKey.keyT, control: true);

    expect(ran, 0);
  }, variant: _linux);

  testWidgets('nothing runs behind an open dialog', (tester) async {
    var ran = 0;
    unregister.add(
      AppCommands.instance.register(AppCommand.newSession, (_) {
        ran++;
        return true;
      }),
    );
    await _pumpApp(tester);
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('form')),
      ),
    );
    await tester.pumpAndSettle();

    await _press(tester, LogicalKeyboardKey.keyT, control: true, shift: true);
    expect(ran, 0);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.keyT, control: true, shift: true);
    expect(ran, 1);
  }, variant: _linux);

  testWidgets('the digit keys pick a tab by position', (tester) async {
    final picked = <int?>[];
    unregister.add(
      AppCommands.instance.register(AppCommand.selectTab, (index) {
        picked.add(index);
        return true;
      }),
    );
    await _pumpApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(picked, [2]);
  }, variant: _linux);

  testWidgets('Esc asks the screens that registered for it, and a screen '
      'with nothing to clear hands it on', (tester) async {
    final calls = <String>[];
    unregister
      ..add(
        AppCommands.instance.registerEscape(() {
          calls.add('first');
          return true;
        }),
      )
      ..add(
        AppCommands.instance.registerEscape(() {
          calls.add('second');
          return false;
        }),
      );
    await _pumpApp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(calls, ['second', 'first']);
  }, variant: _linux);

  testWidgets('a Mac spells its shortcuts with its own symbols', (
    tester,
  ) async {
    expect(AppCommands.shortcutLabel(AppCommand.newSession), '⌘T');
    expect(AppCommands.shortcutLabel(AppCommand.previousTab), '⌃⇧Tab');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('every command but the tab digits has a shortcut', () {
    for (final command in AppCommand.values) {
      if (command == AppCommand.selectTab) continue;
      expect(
        AppCommands.activatorsFor(command),
        isNotEmpty,
        reason: '$command',
      );
    }
  });
}

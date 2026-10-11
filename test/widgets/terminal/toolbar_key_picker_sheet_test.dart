import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/widgets/terminal/toolbar_key_picker_sheet.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  late List<String?> results;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    results = [];
  });

  Future<void> open(WidgetTester tester, {ToolbarAction? initial}) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(
                await showCustomKeyEditor(context, initial: initial),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text(t.common.save));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the capture box raises the keyboard again', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );

    await open(tester);
    calls.clear();

    final preview = tester.getRect(find.text(t.toolbar.comboAwaitingKey));
    await tester.tapAt(preview.centerLeft - const Offset(24, 0));
    await tester.pumpAndSettle();

    expect(calls, contains('TextInput.show'));
  });

  bool canSave(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, t.common.save),
          )
          .onPressed !=
      null;

  group('opening the editor', () {
    testWidgets('starts on a new key with nothing to save yet', (tester) async {
      await open(tester);

      expect(find.text(t.toolbar.newCustomKey), findsOneWidget);
      expect(canSave(tester), isFalse);
    });

    testWidgets('offers both kinds of key', (tester) async {
      await open(tester);
      expect(find.text(t.toolbar.comboMode), findsOneWidget);
      expect(find.text(t.toolbar.textMode), findsOneWidget);
    });

    testWidgets('titles itself as an edit when it was given one', (
      tester,
    ) async {
      await open(
        tester,
        initial: toolbarActionForId(toolbarCustomActionId(text: 'deploy')),
      );
      expect(find.text(t.toolbar.editCustomKey), findsOneWidget);
      expect(find.text(t.toolbar.newCustomKey), findsNothing);
    });
  });

  group('a text key', () {
    Future<void> openTextMode(WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text(t.toolbar.textMode));
      await tester.pumpAndSettle();
    }

    testWidgets('cannot be saved empty', (tester) async {
      await openTextMode(tester);
      expect(canSave(tester), isFalse);
    });

    testWidgets('saves what was typed as a custom key id', (tester) async {
      await openTextMode(tester);
      await tester.enterText(find.byType(TextField).last, 'sudo -i');
      await tester.pumpAndSettle();
      expect(canSave(tester), isTrue);

      await save(tester);

      expect(results, hasLength(1));
      expect(results.single, toolbarCustomActionId(text: 'sudo -i'));
      expect(toolbarActionForId(results.single!), isNotNull);
    });

    testWidgets('remembers the text it was opened on', (tester) async {
      await open(
        tester,
        initial: toolbarActionForId(
          toolbarCustomActionId(text: 'systemctl status'),
        ),
      );
      expect(find.text('systemctl status'), findsWidgets);
    });

    testWidgets('can be told to press Enter afterwards', (tester) async {
      await openTextMode(tester);
      await tester.enterText(find.byType(TextField).last, 'ls');
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.toolbar.customAppendEnter));
      await tester.pumpAndSettle();
      await save(tester);

      final withEnter = results.single!;
      expect(isValidToolbarActionId(withEnter), isTrue);
      expect(withEnter, isNot(toolbarCustomActionId(text: 'ls')));
      expect(withEnter, toolbarCustomActionId(text: 'ls', appendEnter: true));
    });
  });

  group('a modifier combo', () {
    testWidgets('cannot be saved before a key has been pressed', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('CTRL'));
      await tester.pumpAndSettle();

      expect(canSave(tester), isFalse);
      expect(find.textContaining(t.toolbar.comboAwaitingKey), findsWidgets);
    });

    testWidgets('shows which modifiers are armed', (tester) async {
      await open(tester);
      await tester.tap(find.text('CTRL'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ctrl+'), findsWidgets);

      await tester.tap(find.text('SHIFT'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ctrl+Shift+'), findsWidgets);
    });

    testWidgets('explains the keys a soft keyboard cannot send', (
      tester,
    ) async {
      await open(tester);
      expect(find.text(t.toolbar.comboSpecialKeys), findsOneWidget);
    });
  });

  testWidgets('backing out saves nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(PhosphorIconsRegular.x));
    await tester.pumpAndSettle();

    expect(results, [null]);
  });
}

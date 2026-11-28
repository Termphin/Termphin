import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/widgets/ui/save_shortcuts.dart';

void main() {
  testWidgets(
    'on a desktop Ctrl+S saves the moment the form opens, before any click',
    (tester) async {
      var saved = 0;
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => SaveShortcuts(
            onSave: () => saved++,
            child: const Scaffold(body: Text('form')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saved, 1);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('a phone does not take the focus for the form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SaveShortcuts(onSave: () {}, child: const Scaffold()),
      ),
    );
    await tester.pumpAndSettle();
    final focus = tester.widget<Focus>(
      find
          .descendant(
            of: find.byType(SaveShortcuts),
            matching: find.byType(Focus),
          )
          .first,
    );
    expect(focus.autofocus, isFalse);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
    'on a desktop Ctrl+S still saves after a nested dialog pops and drops focus',
    (tester) async {
      var saved = 0;
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        DialogRoute<void>(
          context: navigator.context,
          builder: (formCtx) => SaveShortcuts(
            onSave: () => saved++,
            child: Scaffold(
              body: Builder(
                builder: (btnCtx) => ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: formCtx,
                      builder: (dlgCtx) => AlertDialog(
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                            child: const Text('Accept'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Test'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      FocusScope.of(tester.element(find.byType(SaveShortcuts))).unfocus();
      await tester.pump();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saved, 1);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}

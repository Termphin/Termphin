import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart' as re;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/editor_settings_screen.dart';
import 'package:termphin/services/settings/editor_settings.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await editorSettings.load();
  });

  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(tester, const EditorSettingsScreen());
    await tester.pumpAndSettle();
  }

  re.CodeEditor preview(WidgetTester tester) =>
      tester.widget<re.CodeEditor>(find.byType(re.CodeEditor));

  testWidgets('the preview is the editor, drawn with the settings', (
    tester,
  ) async {
    await pump(tester);

    expect(preview(tester).readOnly, isTrue);
    expect(preview(tester).style!.fontSize, editorSettings.fontSize.value);
    expect(find.byType(re.DefaultCodeLineNumber), findsWidgets);
  });

  testWidgets('switches write straight through and the preview follows', (
    tester,
  ) async {
    await pump(tester);

    final lineNumbersSwitch = find.descendant(
      of: find.ancestor(
        of: find.text(t.settings.editorLineNumbers),
        matching: find.byType(SwitchListTile),
      ),
      matching: find.byType(Switch),
    );
    await tester.tap(lineNumbersSwitch);
    await tester.pumpAndSettle();

    expect(editorSettings.lineNumbers.value, isFalse);
    expect(find.byType(re.DefaultCodeLineNumber), findsNothing);
  });
}

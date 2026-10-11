import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/screens/settings/terminal_appearance_screen.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/terminal/terminal_preview.dart';

import '../../support/test_app.dart';

/// The screen reads the settings straight out of memory, so a test that
/// seeds preferences has to put them back through the readers first.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    return terminalSettings.load();
  });

  TerminalPreview preview(WidgetTester tester) =>
      tester.widget<TerminalPreview>(find.byType(TerminalPreview));

  testWidgets('previews the settings it is editing', (tester) async {
    SharedPreferences.setMockInitialValues({
      kTerminalSchemePrefsKey: 'dracula',
      kTerminalFontSizePrefsKey: 14.0,
      kTerminalCursorStylePrefsKey: 'bar',
    });
    await terminalSettings.load();

    await pumpTestApp(tester, const TerminalAppearanceScreen());
    await tester.pumpAndSettle();

    final shown = preview(tester);
    expect(shown.scheme, AppTheme.terminalSchemeDracula);
    expect(shown.fontSize, 14.0);
    expect(shown.cursorStyle, 'bar');
  });

  testWidgets('a size change reaches the preview and the disk', (tester) async {
    await pumpTestApp(tester, const TerminalAppearanceScreen());
    await tester.pumpAndSettle();
    expect(preview(tester).fontSize, 12.0);

    await tester.tap(find.byIcon(PhosphorIconsRegular.plus).first);
    await tester.pumpAndSettle();

    expect(preview(tester).fontSize, 12.5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kTerminalFontSizePrefsKey), 12.5);
    expect(terminalSettings.fontSize.value, 12.5);
  });

  testWidgets('the cursor switch shows in the preview', (tester) async {
    await pumpTestApp(tester, const TerminalAppearanceScreen());
    await tester.pumpAndSettle();
    expect(preview(tester).cursorBlink, isTrue);

    await tester.ensureVisible(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(preview(tester).cursorBlink, isFalse);
    expect(await terminalSettings.cursorBlink.load(), isFalse);
  });
}

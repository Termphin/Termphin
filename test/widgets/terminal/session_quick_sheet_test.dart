import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/terminal/session_quick_sheet.dart';
import 'package:termphin/widgets/terminal/terminal_scheme_theme.dart';
import 'package:termphin/widgets/ui/toolbar_key_button.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  late List<String> exits;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    await terminalSettings.load();
    exits = [];
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(
        ToolbarProfile(
          id: 'vim',
          name: 'Vim',
          layout: clampToolbarLayout(
            const ToolbarLayout(
              order: ['esc', 'sym_slash', '', 'tab'],
              columns: 4,
              rows: 1,
              pages: 1,
            ),
          ),
        ),
        activate: false,
      ),
    );
  });

  Future<void> open(WidgetTester tester, {bool showToolbarTab = true}) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSessionQuickSheet(
                context,
                showToolbarTab: showToolbarTab,
                onManageToolbars: () => exits.add('toolbars'),
                onOpenAppearance: () => exits.add('appearance'),
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

  Finder card(String id) => find.byKey(ValueKey('toolbarProfileCard-$id'));

  testWidgets('every layout is drawn with its own keys', (tester) async {
    await open(tester);

    expect(find.text('Vim'), findsOneWidget);
    expect(find.text(t.settings.toolbarProfileDefault), findsOneWidget);
    final vimKeys = tester
        .widgetList<ToolbarKeyButton>(
          find.descendant(
            of: card('vim'),
            matching: find.byType(ToolbarKeyButton),
          ),
        )
        .map((key) => key.label);
    expect(vimKeys, ['ESC', '/', 'TAB']);
  });

  testWidgets('tapping a layout hands the toolbar to it and closes', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(card('vim'));
    await tester.pumpAndSettle();

    expect(toolbarSettings.profiles.value.activeId, 'vim');
    expect(toolbarSettings.layout.value.columns, 4);
    expect(card('vim'), findsNothing);
  });

  testWidgets('manage layouts closes the sheet before it opens anything', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text(t.toolbar.manageLayouts));
    await tester.pumpAndSettle();

    expect(exits, ['toolbars']);
    expect(card('vim'), findsNothing);
  });

  testWidgets('the appearance tab writes the terminal settings through', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('sessionQuickTab-appearance')));
    await tester.pumpAndSettle();
    expect(card('vim'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('quickSchemeField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nord').last);
    await tester.pumpAndSettle();
    expect(terminalSettings.scheme.value, 'nord');

    await tester.tap(find.byKey(const ValueKey('quickFontField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JetBrains Mono').last);
    await tester.pumpAndSettle();
    expect(terminalSettings.fontFamily.value, 'JetBrainsMonoNerdFontMono');

    await tester.ensureVisible(find.text(t.toolbar.allTerminalSettings));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.toolbar.allTerminalSettings));
    await tester.pumpAndSettle();
    expect(exits, ['appearance']);
  });

  testWidgets('switching tabs keeps the sheet the same height', (
    tester,
  ) async {
    await open(tester);
    final surface = find.byKey(const ValueKey('sessionQuickSurface'));
    final toolbarHeight = tester.getSize(surface).height;

    await tester.tap(find.byKey(const ValueKey('sessionQuickTab-appearance')));
    await tester.pumpAndSettle();

    expect(tester.getSize(surface).height, toolbarHeight);
  });

  testWidgets('with the toolbar off only the appearance is offered', (
    tester,
  ) async {
    await open(tester, showToolbarTab: false);

    expect(find.byKey(const ValueKey('sessionQuickTab-toolbar')), findsNothing);
    expect(card('vim'), findsNothing);
    expect(find.byKey(const ValueKey('quickSchemeField')), findsOneWidget);
  });

  testWidgets('the sheet repaints in a scheme picked while it is open', (
    tester,
  ) async {
    resetTerminalChromeScheme();
    addTearDown(resetTerminalChromeScheme);
    await open(tester, showToolbarTab: false);

    Color sheetColor() {
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('sessionQuickSurface')),
      );
      return (box.decoration as ShapeDecoration).color!;
    }

    final before = sheetColor();

    await terminalSettings.scheme.set('light');
    await tester.pumpAndSettle();

    expect(
      sheetColor(),
      AppColors.fromTerminalScheme(
        AppTheme.terminalSchemeForId('light'),
      ).surfaceCard,
    );
    expect(sheetColor(), isNot(before));
  });
}

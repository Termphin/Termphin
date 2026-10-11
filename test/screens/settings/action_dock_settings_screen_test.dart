import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/action_dock_settings_screen.dart';
import 'package:termphin/services/settings/action_dock_settings.dart';
import 'package:termphin/widgets/ui/action_dock_tile.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  test('a fresh install shows only the first four actions', () async {
    SharedPreferences.setMockInitialValues({});

    await actionDockSettings.load();

    expect(actionDockSettings.hidden.value, kDefaultHiddenDockActions);
    final visible = actionDockSettings.order.value
        .where((a) => !actionDockSettings.hidden.value.contains(a))
        .toList();
    expect(visible, [
      DockAction.insertSnippet,
      DockAction.uploadFile,
      DockAction.paste,
      DockAction.search,
    ]);
  });

  test(
    'an empty stored list means "show everything", not the defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'command_palette_hidden': <String>[],
      });

      await actionDockSettings.load();

      expect(actionDockSettings.hidden.value, isEmpty);
    },
  );

  testWidgets('the editor previews the palette and trays the hidden ones', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    expect(
      find.byType(ActionDockTile),
      findsNWidgets(DockAction.values.length),
    );
    expect(find.text(t.settings.actionDockPreview), findsOneWidget);
    expect(find.text(t.settings.actionDockHiddenLabel), findsOneWidget);
  });

  testWidgets('tapping a hidden tile puts it back on the palette', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text(dockActionLabel(t, DockAction.viewLog)));
    await tester.pumpAndSettle();

    expect(
      actionDockSettings.hidden.value.contains(DockAction.viewLog),
      isFalse,
    );
  });

  testWidgets('tapping a palette tile moves it to the tray', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text(dockActionLabel(t, DockAction.paste)));
    await tester.pumpAndSettle();

    expect(actionDockSettings.hidden.value.contains(DockAction.paste), isTrue);
  });
}

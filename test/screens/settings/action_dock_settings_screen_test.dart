import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

  group('placeDockAction', () {
    const layout = kDefaultDockLayout;

    test('moving a tile back inserts it before the target', () {
      final next = placeDockAction(layout, DockAction.search, 0);

      expect(next.order.take(4), [
        DockAction.search,
        DockAction.insertSnippet,
        DockAction.uploadFile,
        DockAction.paste,
      ]);
    });

    test('moving a tile forward inserts it after the target', () {
      final next = placeDockAction(layout, DockAction.insertSnippet, 2);

      expect(next.order.take(4), [
        DockAction.uploadFile,
        DockAction.paste,
        DockAction.insertSnippet,
        DockAction.search,
      ]);
    });

    test('a hidden tile is shown at the given place', () {
      final next = placeDockAction(layout, DockAction.viewLog, 1);

      expect(next.hidden.contains(DockAction.viewLog), isFalse);
      expect(next.order.take(5), [
        DockAction.insertSnippet,
        DockAction.viewLog,
        DockAction.uploadFile,
        DockAction.paste,
        DockAction.search,
      ]);
    });
  });

  test('hiding puts the action last, behind every visible one', () {
    final next = hideDockAction((
      order: DockAction.values,
      hidden: {DockAction.paste},
    ), DockAction.insertSnippet);

    expect(next.hidden, {DockAction.paste, DockAction.insertSnippet});
    expect(next.order.first, DockAction.uploadFile);
    expect(next.order.last, DockAction.insertSnippet);
    expect(
      next.order.indexOf(DockAction.paste),
      greaterThan(next.order.indexOf(DockAction.viewLog)),
    );
  });

  testWidgets('tapping a hidden tile puts it back at the end of the dock', (
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
    expect(actionDockSettings.order.value[4], DockAction.viewLog);
  });

  testWidgets('a stray tap on a dock tile hides nothing', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text(dockActionLabel(t, DockAction.paste)));
    await tester.pumpAndSettle();

    expect(actionDockSettings.hidden.value, kDefaultHiddenDockActions);
  });

  testWidgets('the minus badge moves a dock tile to the tray', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip(
        t.settings.actionDockHide(name: dockActionLabel(t, DockAction.paste)),
      ),
    );
    await tester.pumpAndSettle();

    expect(actionDockSettings.hidden.value.contains(DockAction.paste), isTrue);
  });

  testWidgets('dragging a tile onto an earlier one inserts, not swaps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    final from = tester.getCenter(
      find.text(dockActionLabel(t, DockAction.paste)),
    );
    final to = tester.getCenter(
      find.text(dockActionLabel(t, DockAction.insertSnippet)),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(actionDockSettings.order.value.take(4), [
      DockAction.paste,
      DockAction.insertSnippet,
      DockAction.uploadFile,
      DockAction.search,
    ]);
  });

  testWidgets('a hidden tile dragged onto the dock lands where it is dropped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    final from = tester.getCenter(
      find.text(dockActionLabel(t, DockAction.copyPath)),
    );
    final to = tester.getCenter(
      find.text(dockActionLabel(t, DockAction.uploadFile)),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      actionDockSettings.hidden.value.contains(DockAction.copyPath),
      isFalse,
    );
    expect(actionDockSettings.order.value.take(3), [
      DockAction.insertSnippet,
      DockAction.copyPath,
      DockAction.uploadFile,
    ]);
  });

  testWidgets('on a desktop a plain mouse drag moves a tile, no long press', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    final from = tester.getCenter(
      find.text(dockActionLabel(t, DockAction.search)),
    );
    final to = tester.getCenter(
      find.text(dockActionLabel(t, DockAction.insertSnippet)),
    );
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(actionDockSettings.order.value.first, DockAction.search);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('reset brings back the default dock', (tester) async {
    SharedPreferences.setMockInitialValues({
      'command_palette_hidden': <String>[],
      'command_palette_order': [
        for (final a in DockAction.values.reversed) a.name,
      ],
    });

    await pumpTestApp(tester, const ActionDockSettingsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.settings.actionDockReset));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.reset));
    await tester.pumpAndSettle();

    expect(actionDockSettings.order.value, DockAction.values);
    expect(actionDockSettings.hidden.value, kDefaultHiddenDockActions);
  });
}

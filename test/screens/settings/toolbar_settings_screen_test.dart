import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/toolbar_settings_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/widgets/ui/toolbar_key_button.dart';

import '../../support/test_app.dart';

/// A toolbar key is only picked up on a hold, never a plain drag - the pool
/// below the grid scrolls under the same gesture, so a quick pan used to
/// rearrange the layout by accident. Picking one up measures its target slot
/// before the move, which is what lets the source slot empty out and every
/// key after it renumber.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    toolbarSettings.customKeys.value = const [];
  });

  /// Opens the editor on the layout the toolbar is currently drawing, which is
  /// what keeps `toolbarSettings.layout` a fair reading of what was saved.
  Future<void> open(WidgetTester tester, {String? profileId}) async {
    await pumpTestApp(
      tester,
      ToolbarSettingsScreen(
        profileId: profileId ?? toolbarSettings.profiles.value.activeId,
      ),
    );
    await tester.pumpAndSettle();
  }

  final gridButton = find.byTooltip(t.settings.toolbarGridSize);

  testWidgets('the grid draws its slots with the toolbar’s own key widget', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(ToolbarKeyButton), findsWidgets);
    expect(find.text(t.settings.toolbarTapToPlace), findsOneWidget);
  });

  testWidgets('tapping a slot then a pool key places it', (tester) async {
    await open(tester);

    final layout = toolbarSettings.layout.value;
    await saveToolbarLayout(
      layout.copyWith(order: ['', ...layout.order.skip(1)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ToolbarEmptySlot).first);
    await tester.pumpAndSettle();
    expect(find.text(t.settings.toolbarSlotSelected), findsOneWidget);

    await tester.tap(find.widgetWithText(ToolbarKeyButton, 'F4').last);
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.order.first, 'f4');
    expect(find.text(t.settings.toolbarTapToPlace), findsOneWidget);
  });

  testWidgets('a key already on the toolbar is never placed twice', (
    tester,
  ) async {
    await open(tester);
    final before = toolbarSettings.layout.value.order;
    expect(before, contains('esc'));

    await tester.tap(find.widgetWithText(ToolbarKeyButton, 'ESC').last);
    await tester.pumpAndSettle();

    final after = toolbarSettings.layout.value.order;
    expect(after.where((id) => id == 'esc'), hasLength(1));
    expect(after, before);
  });

  testWidgets('a key is only picked up on a hold, never on a swipe', (
    tester,
  ) async {
    await open(tester);
    final before = toolbarSettings.layout.value.order;

    final first = find.byType(ToolbarKeyButton).first;
    await tester.drag(first, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(toolbarSettings.layout.value.order, before);

    final target = tester.getCenter(find.byType(ToolbarKeyButton).at(1));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.order, isNot(before));
    expect(toolbarSettings.layout.value.order[1], before.first);
  });

  testWidgets('every slot selects on a tap, filled or not', (tester) async {
    await open(tester);

    await tester.tap(find.byType(ToolbarKeyButton).first);
    await tester.pumpAndSettle();

    expect(find.text('ESC'), findsWidgets);
    expect(find.text(t.settings.toolbarTapToPlace), findsNothing);

    await tester.tap(
      find.widgetWithText(TextButton, t.settings.toolbarSlotRemove),
    );
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.order.first, '');
  });

  testWidgets('removing a key can be undone', (tester) async {
    await open(tester);
    final before = toolbarSettings.layout.value.order;

    await tester.tap(find.byType(ToolbarKeyButton).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, t.settings.toolbarSlotRemove),
    );
    await tester.pumpAndSettle();
    expect(toolbarSettings.layout.value.order.first, '');

    await tester.tap(find.text(t.common.undo));
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.order, before);
  });

  testWidgets('a held key moves to the next slot tapped', (tester) async {
    await open(tester);
    final before = toolbarSettings.layout.value.order;

    await tester.tap(find.byType(ToolbarKeyButton).first);
    await tester.pumpAndSettle();
    expect(find.text(t.settings.toolbarKeyHeld), findsOneWidget);

    await tester.tap(find.byType(ToolbarKeyButton).at(1));
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.order[0], before[1]);
    expect(toolbarSettings.layout.value.order[1], before[0]);
  });

  testWidgets('a held key can be carried onto another page', (tester) async {
    await open(tester);
    final layout = toolbarSettings.layout.value;
    expect(layout.pages, greaterThan(1));
    final carried = layout.order.first;
    final target = layout.slotsPerPage;

    await tester.tap(find.byType(ToolbarKeyButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.settings.layoutLabel(number: 2)));
    await tester.pumpAndSettle();
    expect(find.text(t.settings.toolbarKeyHeld), findsOneWidget);

    await tester.tap(find.byType(ToolbarKeyButton).first);
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.order[target], carried);
    expect(toolbarSettings.layout.value.order.first, layout.order[target]);
  });

  testWidgets('picking a page does not resize its tab', (tester) async {
    await open(tester);
    expect(toolbarSettings.layout.value.pages, greaterThan(1));

    final second = find.text(t.settings.layoutLabel(number: 2));
    final before = tester.getSize(
      find.ancestor(of: second, matching: find.byType(ChoiceChip)),
    );

    await tester.tap(second);
    await tester.pumpAndSettle();

    final after = tester.getSize(
      find.ancestor(of: second, matching: find.byType(ChoiceChip)),
    );
    expect(after, before);
  });

  testWidgets('resetting the layout asks first and can be undone', (
    tester,
  ) async {
    await open(tester);
    final layout = toolbarSettings.layout.value;
    await saveToolbarLayout(
      layout.copyWith(order: ['', ...layout.order.skip(1)]),
    );
    await tester.pumpAndSettle();
    final before = toolbarSettings.layout.value.order;

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.toolbarReset));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.toolbarResetTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, t.common.reset));
    await tester.pumpAndSettle();
    expect(toolbarSettings.layout.value.order, ToolbarLayout.defaults.order);

    await tester.tap(find.text(t.common.undo));
    await tester.pumpAndSettle();
    expect(toolbarSettings.layout.value.order, before);
  });

  testWidgets('shrinking the grid asks before it drops keys', (tester) async {
    await open(tester);
    final before = toolbarSettings.layout.value;

    await tester.tap(gridButton);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Row, t.settings.toolbarColumns),
        matching: find.byIcon(PhosphorIconsRegular.minus),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.settings.toolbarResizeTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('\$'),
      ),
      findsNothing,
    );
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.columns, before.columns);
    expect(toolbarSettings.layout.value.order, before.order);
  });

  testWidgets('confirming the shrink applies it', (tester) async {
    await open(tester);

    await tester.tap(gridButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Row, t.settings.toolbarColumns),
        matching: find.byIcon(PhosphorIconsRegular.minus),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.toolbarResizeConfirm));
    await tester.pumpAndSettle();

    expect(toolbarSettings.layout.value.columns, kToolbarColumns - 1);
  });

  testWidgets('the pool search filters what can be placed', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'page');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ToolbarKeyButton, 'PAGE↑'), findsWidgets);
    expect(find.widgetWithText(ToolbarKeyButton, 'F7'), findsNothing);
  });

  testWidgets('the grid sheet follows its own steppers without reopening', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(gridButton);
    await tester.pumpAndSettle();

    final rowsStepper = find.widgetWithText(Row, t.settings.toolbarRows);
    expect(
      find.descendant(of: rowsStepper, matching: find.text('$kToolbarRows')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: rowsStepper,
        matching: find.byIcon(PhosphorIconsRegular.plus),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: rowsStepper,
        matching: find.text('${kToolbarRows + 1}'),
      ),
      findsOneWidget,
    );
    expect(toolbarSettings.layout.value.rows, kToolbarRows + 1);
  });

  testWidgets('editing a layout that is not in use leaves the toolbar alone', (
    tester,
  ) async {
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(
        ToolbarProfile(id: 'other', name: 'Logs', layout: ToolbarLayout.blank),
        activate: false,
      ),
    );
    final live = toolbarSettings.layout.value;
    await open(tester, profileId: 'other');

    await tester.tap(find.byType(ToolbarEmptySlot).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ToolbarKeyButton, 'F4').last);
    await tester.pumpAndSettle();

    expect(toolbarProfileLayout('other').order.first, 'f4');
    expect(toolbarSettings.profiles.value.activeId, isNot('other'));
    expect(toolbarSettings.layout.value, live);
  });
}

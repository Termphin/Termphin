import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/toolbar_profiles_screen.dart';
import 'package:termphin/screens/settings/toolbar_settings_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  Future<void> open(WidgetTester tester) async {
    await pumpTestApp(tester, const ToolbarProfilesScreen());
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh install lists the one layout it has', (tester) async {
    await open(tester);

    expect(find.text(t.settings.toolbarProfileDefault), findsOneWidget);
    expect(find.text(t.settings.toolbarProfileActive.toUpperCase()), findsOne);
  });

  testWidgets('a new layout starts empty and opens for editing', (
    tester,
  ) async {
    await open(tester);

    expect(find.text(t.settings.toolbarProfileNew), findsOneWidget);
    await tester.tap(find.text(t.settings.toolbarProfileNew));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Vim');
    await tester.tap(find.widgetWithText(TextButton, t.common.save));
    await tester.pumpAndSettle();

    expect(find.byType(ToolbarSettingsScreen), findsOneWidget);
    expect(toolbarSettings.profiles.value.profiles, hasLength(2));
    expect(toolbarSettings.profiles.value.profiles.last.name, 'Vim');
    expect(
      toolbarSettings.profiles.value.profiles.last.layout.order.where(
        (id) => id.isNotEmpty,
      ),
      isEmpty,
    );
    expect(toolbarSettings.profiles.value.active.name, isNot('Vim'));
    expect(
      toolbarSettings.layout.value.order.where((id) => id.isNotEmpty),
      isNotEmpty,
    );
  });

  Future<void> addLogsProfile() => saveToolbarProfiles(
    toolbarSettings.profiles.value.added(
      ToolbarProfile(
        id: 'other',
        name: 'Logs',
        layout: ToolbarLayout.blank.copyWith(buttonHeight: 31),
      ),
      activate: false,
    ),
  );

  testWidgets('tapping a layout picks it and stays put', (tester) async {
    await addLogsProfile();
    await open(tester);

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();

    expect(toolbarSettings.profiles.value.activeId, 'other');
    expect(toolbarSettings.layout.value.buttonHeight, 31);
    expect(find.byType(ToolbarSettingsScreen), findsNothing);
  });

  testWidgets('the overflow menu opens the editor without switching', (
    tester,
  ) async {
    await addLogsProfile();
    await open(tester);
    final activeBefore = toolbarSettings.profiles.value.activeId;

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.edit).last);
    await tester.pumpAndSettle();

    expect(find.byType(ToolbarSettingsScreen), findsOneWidget);
    expect(toolbarSettings.profiles.value.activeId, activeBefore);
  });

  testWidgets('the only layout refuses to be deleted', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(PhosphorIconsRegular.dotsThreeVertical).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.delete).last);
    await tester.pumpAndSettle();

    expect(find.text(t.settings.toolbarProfileDeleteLast), findsOneWidget);
    expect(find.text(t.settings.toolbarProfileDeleteTitle), findsNothing);
    expect(toolbarSettings.profiles.value.profiles, hasLength(1));
  });
}

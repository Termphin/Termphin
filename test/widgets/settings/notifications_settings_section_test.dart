import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/notifications_settings_screen.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/widgets/settings/notifications_settings_section.dart';
import 'package:termphin/widgets/ui/app_card.dart';
import 'package:termphin/widgets/ui/large_title_scaffold.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    return terminalSettings.load();
  });

  testWidgets('the agent notices render and toggle their settings', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsList()),
      ),
    );
    await tester.pumpAndSettle();

    for (final (title, setting) in [
      (
        t.settings.finishedNotifications,
        terminalSettings.finishedNotifications,
      ),
      (t.settings.quietNotifications, terminalSettings.quietNotifications),
      (t.settings.noticeLines, terminalSettings.noticeLines),
    ]) {
      expect(find.text(title), findsOneWidget);
      expect(setting.value, isTrue);

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      expect(setting.value, isFalse);
    }
  });

  testWidgets('settings keep one row that opens the notifications screen', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsSection()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.settings.finishedNotifications), findsNothing);
    expect(find.text(t.settings.notificationsRowSubtitle), findsOneWidget);

    await tester.tap(find.text(t.settings.notificationsRowSubtitle));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.finishedNotifications), findsOneWidget);
    expect(find.text(t.settings.quietNotifications), findsOneWidget);
  });

  testWidgets('the screen title lines up with the card below it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpTestApp(tester, const NotificationsSettingsScreen());
    await tester.pumpAndSettle();

    final title = tester.getTopLeft(
      find.descendant(
        of: find.byType(LargeTitleHeader),
        matching: find.text(t.settings.notificationsSection),
      ),
    );
    final card = tester.getTopLeft(find.byType(AppCard).first);
    expect(title.dx, card.dx);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/pro/pro_paywall_screen.dart';
import 'package:termphin/screens/settings/notifications_settings_screen.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/widgets/settings/notifications_settings_section.dart';
import 'package:termphin/widgets/ui/app_card.dart';
import 'package:termphin/widgets/ui/large_title_scaffold.dart';

import '../../support/fake_account_backend.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    return terminalSettings.load();
  });

  testWidgets('one switch turns every kind of notice on and off together', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsList()),
      ),
    );
    await tester.pumpAndSettle();
    final kinds = [
      terminalSettings.programNotifications,
      terminalSettings.finishedNotifications,
      terminalSettings.quietNotifications,
    ];
    expect(kinds.map((kind) => kind.value), everyElement(isTrue));

    await tester.tap(find.text(t.settings.commandNotifications));
    await tester.pumpAndSettle();
    expect(kinds.map((kind) => kind.value), everyElement(isFalse));
    expect(terminalSettings.noticeLines.value, isTrue);

    await tester.tap(find.text(t.settings.noticeLines));
    await tester.pumpAndSettle();
    expect(terminalSettings.noticeLines.value, isFalse);
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

    expect(find.text(t.settings.commandNotifications), findsNothing);
    expect(find.text(t.settings.notificationsRowSubtitle), findsOneWidget);

    await tester.tap(find.text(t.settings.notificationsRowSubtitle));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.commandNotifications), findsOneWidget);
    expect(find.text(t.settings.noticeLines), findsOneWidget);
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

  testWidgets('without Pro the setting has no switch but a way to the plans', (
    tester,
  ) async {
    AccountService.backendOverride = () => FakeAccountBackend();
    AccountService.instance.resetForTest();
    addTearDown(() {
      AccountService.backendOverride = null;
      AccountService.instance.resetForTest();
    });
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: NotificationsSettingsList()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.settings.notifyWhenClosed), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.text(t.settings.seePro), findsOneWidget);

    await tester.tap(find.text(t.settings.seePro));
    await tester.pumpAndSettle();

    expect(find.byType(ProPaywallScreen), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/widgets/settings/notifications_settings_section.dart';

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
        body: SingleChildScrollView(child: NotificationsSettingsSection()),
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
}

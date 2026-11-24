import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/pro/pro_features_screen.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/live_presence_setting.dart';
import 'package:termphin/widgets/account/live_status_card.dart';
import 'package:termphin/widgets/account/pro_card.dart';
import 'package:termphin/widgets/account/pro_feature_sheet.dart';
import 'package:termphin/widgets/account/sync_card.dart';
import 'package:termphin/widgets/pro/feature_demos.dart';
import 'package:termphin/widgets/pro/pro_benefits.dart';
import 'package:termphin/widgets/settings/notifications_settings_section.dart';

import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
    await loadAppSettings();
    await livePresenceSetting.load();
    ProService.instance.active.value = true;
  });

  tearDown(() => ProService.instance.active.value = false);

  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(tester, const ProFeaturesScreen());
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('everything Pro adds is on one screen, and nothing free', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(NotifyWhenClosedTiles), findsOneWidget);
    expect(find.text(t.settings.notifyWhenClosed), findsOneWidget);
    expect(find.text(t.settings.commandNotifications), findsNothing);
    expect(find.text(t.settings.noticeLines), findsNothing);
    expect(find.byType(LiveStatusCard), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(SyncCard), 200);
    expect(find.byType(SyncCard), findsOneWidget);
    expect(find.byType(ProCard), findsNothing);
  });

  testWidgets('every Pro benefit has its section', (tester) async {
    await pump(tester);

    for (final benefit in ProBenefit.values) {
      final row = find.byKey(ValueKey('proBenefit-${benefit.name}'));
      await tester.scrollUntilVisible(row, 200);
      expect(row, findsOneWidget);
    }
  });

  testWidgets('how it works shows the live demo', (tester) async {
    await pump(tester);

    final live = find.byKey(const ValueKey('howItWorks-liveStatus'));
    await tester.ensureVisible(live);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(live);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.widget<FeatureDemo>(find.byType(FeatureDemo)).kind,
      FeatureDemoKind.live,
    );
    expect(
      find.descendant(
        of: find.byType(ProFeatureSheet),
        matching: find.text(t.proFeature.liveTitle),
      ),
      findsOneWidget,
    );
  });
}

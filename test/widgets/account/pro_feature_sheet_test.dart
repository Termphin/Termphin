import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/widgets/account/pro_feature_sheet.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await terminalSettings.load();
    ProService.instance.active.value = false;
  });

  tearDown(() => ProService.instance.active.value = false);

  testWidgets('the Pro chip shows for an account without Pro', (tester) async {
    await pumpTestApp(
      tester,
      const ProFeatureChip(feature: ProFeature.notifications),
    );

    expect(find.text(t.account.pro.badge), findsOneWidget);
  });

  testWidgets('the Pro chip is gone once the account has Pro', (tester) async {
    ProService.instance.active.value = true;
    await pumpTestApp(
      tester,
      const ProFeatureChip(feature: ProFeature.notifications),
    );

    expect(find.text(t.account.pro.badge), findsNothing);
  });

  testWidgets('tapping the chip explains the feature in a sheet', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const ProFeatureChip(feature: ProFeature.notifications),
    );

    await tester.tap(find.text(t.account.pro.badge));
    await tester.pumpAndSettle();

    expect(find.text(t.proFeature.notificationsTitle), findsOneWidget);
    expect(find.text(t.proFeature.notificationsBody), findsOneWidget);
    expect(find.text(t.proFeature.seePro), findsOneWidget);
  });
}

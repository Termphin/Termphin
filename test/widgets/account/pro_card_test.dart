import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/widgets/account/pro_card.dart';
import 'package:termphin/widgets/ui/settings_tile.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  tearDown(() {
    ProService.instance.active.value = false;
    ProService.instance.boughtOnWeb.value = false;
  });

  testWidgets('Pro from a store leads to where the store manages it', (
    tester,
  ) async {
    ProService.instance.active.value = true;
    await pumpTestApp(tester, const Scaffold(body: ProCard()));

    expect(find.text(t.account.pro.manage), findsOneWidget);
    expect(find.byKey(const ValueKey('proBoughtOnWeb')), findsNothing);
  });

  testWidgets(
    'Pro bought on the web says so on a phone, with no link out',
    (tester) async {
      ProService.instance.active.value = true;
      ProService.instance.boughtOnWeb.value = true;
      await pumpTestApp(tester, const Scaffold(body: ProCard()));

      final row = tester.widget<SettingsTile>(
        find.byKey(const ValueKey('proBoughtOnWeb')),
      );
      expect(row.onTap, isNull);
      expect(row.trailing, SettingsTileTrailing.none);
      expect(find.text(t.account.pro.boughtOnWeb), findsOneWidget);
      expect(find.text(t.account.pro.manage), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'on a desktop Pro bought on the web leads to the plan on the web',
    (tester) async {
      ProService.instance.active.value = true;
      ProService.instance.boughtOnWeb.value = true;
      await pumpTestApp(tester, const Scaffold(body: ProCard()));

      final row = tester.widget<SettingsTile>(
        find.byKey(const ValueKey('proBoughtOnWeb')),
      );
      expect(row.onTap, isNotNull);
      expect(row.trailing, SettingsTileTrailing.external);
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets('without Pro there is neither row', (tester) async {
    ProService.instance.boughtOnWeb.value = true;
    await pumpTestApp(tester, const Scaffold(body: ProCard()));

    expect(find.byKey(const ValueKey('proBoughtOnWeb')), findsNothing);
    expect(find.text(t.account.pro.manage), findsNothing);
  });
}

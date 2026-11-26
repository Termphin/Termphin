import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/widgets/account/live_status_card.dart';
import 'package:termphin/widgets/pro/feature_demos.dart';

import '../../support/test_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ProService.instance.active.value = false);

  testWidgets('without Pro it points at the paywall', (tester) async {
    ProService.instance.active.value = false;
    await pumpTestApp(tester, const Scaffold(body: LiveStatusCard()));
    expect(find.text('Live status'), findsOneWidget);
    expect(find.text('See Pro'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('without Pro a tap shows how it works before the paywall', (
    tester,
  ) async {
    ProService.instance.active.value = false;
    await pumpTestApp(tester, const Scaffold(body: LiveStatusCard()));

    await tester.tap(find.text('Live status'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(FeatureDemo), findsOneWidget);
    expect(find.text('Your machines, live'), findsOneWidget);
  });

  testWidgets('with Pro it says what it does, with nothing to switch', (
    tester,
  ) async {
    ProService.instance.active.value = true;
    await pumpTestApp(tester, const Scaffold(body: LiveStatusCard()));
    expect(find.text('Live status'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('with Pro how it works sits under the switch and shows the '
      'demo', (tester) async {
    ProService.instance.active.value = true;
    await pumpTestApp(tester, const Scaffold(body: LiveStatusCard()));

    await tester.tap(find.text('How it works'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.widget<FeatureDemo>(find.byType(FeatureDemo)).kind,
      FeatureDemoKind.live,
    );
  });
}

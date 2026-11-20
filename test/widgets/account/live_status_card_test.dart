import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/services/settings/live_presence_setting.dart';
import 'package:termphin/widgets/account/live_status_card.dart';

import '../../support/test_app.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await livePresenceSetting.load();
  });
  tearDown(() => ProService.instance.active.value = false);

  testWidgets('without Pro it points at the paywall', (tester) async {
    ProService.instance.active.value = false;
    await pumpTestApp(tester, const Scaffold(body: LiveStatusCard()));
    expect(find.text('Live status'), findsOneWidget);
    expect(find.text('See Pro'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('with Pro it is a switch, off until turned on', (tester) async {
    ProService.instance.active.value = true;
    await pumpTestApp(tester, const Scaffold(body: LiveStatusCard()));
    expect(livePresenceSetting.value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(livePresenceSetting.value, isTrue);
  });
}

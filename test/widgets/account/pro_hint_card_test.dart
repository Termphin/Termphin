import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/pro/pro_hints.dart';
import 'package:termphin/widgets/account/pro_hint_card.dart';
import 'package:termphin/widgets/ui/app_card.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProHints.instance.reset();
  });

  tearDown(ProHints.instance.reset);

  testWidgets('renders nothing while no hint is up', (tester) async {
    await pumpTestApp(tester, const ProHintCard());

    expect(find.byType(AppCard), findsNothing);
    expect(find.text(t.proHints.action), findsNothing);
  });

  testWidgets('shows the hint with a way to Pro', (tester) async {
    await pumpTestApp(tester, const ProHintCard());

    ProHints.instance.showNow(ProHint.longCommand);
    await tester.pumpAndSettle();

    expect(find.byType(AppCard), findsOneWidget);
    expect(find.text(t.proHints.longCommand), findsOneWidget);
    expect(find.text(t.proHints.action), findsOneWidget);
  });

  testWidgets('closing the card takes it off the screen', (tester) async {
    await pumpTestApp(tester, const ProHintCard());
    ProHints.instance.showNow(ProHint.longCommand);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.proHints.dismiss));
    await tester.pumpAndSettle();

    expect(ProHints.instance.current.value, isNull);
    expect(find.byType(AppCard), findsNothing);
    expect(find.text(t.proHints.longCommand), findsNothing);
  });
}

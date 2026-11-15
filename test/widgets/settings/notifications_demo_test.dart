import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/widgets/settings/notifications_demo.dart';

import '../../support/test_app.dart';

void main() {
  final demo = AppLocale.en.buildSync().settings.notificationsDemo;

  double height(WidgetTester tester) =>
      tester.getSize(find.byType(NotificationsDemo)).height;

  testWidgets('the frame keeps one height while notifications come and go', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Align(alignment: Alignment.topCenter, child: NotificationsDemo()),
    );
    final start = height(tester);
    expect(start, greaterThan(0));

    for (var i = 0; i < NotificationsDemo.steps * 4; i++) {
      await tester.pump(NotificationsDemo.step * 0.25);
      expect(height(tester), start);
    }
  });

  testWidgets('it plays through and stops on the last two notifications', (
    tester,
  ) async {
    await pumpTestApp(tester, const NotificationsDemo());

    await tester.pumpAndSettle();

    expect(find.text(demo.testsTitle), findsWidgets);
    expect(find.text(demo.waitingTitle), findsWidgets);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with animations off it shows the last two straight away', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const NotificationsDemo(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(demo.testsTitle), findsWidgets);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

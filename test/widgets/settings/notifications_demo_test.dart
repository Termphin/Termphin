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

  testWidgets('it waits for its screen to finish sliding in', (tester) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: NotificationsDemo()),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

    double arriving() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.text(demo.waitingTitle).last,
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(arriving(), 0, reason: 'still sliding in');

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(NotificationsDemo.step * 0.5);
    expect(arriving(), greaterThan(0));
  });
}

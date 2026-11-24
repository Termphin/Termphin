import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/widgets/pro/pro_benefits.dart';
import 'package:termphin/widgets/pro/pro_welcome_dialog.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  final title = find.byKey(const ValueKey('proWelcomeTitle'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProWelcome.resetForTest();
    ProService.instance.active.value = false;
    ProService.instance.since.value = DateTime.now();
  });

  tearDown(() {
    ProWelcome.resetForTest();
    ProService.instance.active.value = false;
    ProService.instance.since.value = null;
  });

  Future<void> host(WidgetTester tester) async {
    reduceMotion(tester);
    await pumpTestApp(tester, const Scaffold(body: SizedBox()));
    ProWelcome.host = () => tester.element(find.byType(Scaffold));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every Pro feature and closes with Later', (tester) async {
    await host(tester);
    ProService.instance.active.value = true;
    ProWelcome.ready();
    await settle(tester);

    expect(title, findsOneWidget);
    for (final benefit in ProBenefit.values) {
      expect(find.text(benefit.title(t)), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('proWelcomeLater')));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
  });

  testWidgets('waits for the launch dialogs, then shows once', (tester) async {
    await host(tester);
    ProService.instance.active.value = true;
    await ProWelcome.maybeShow();
    await settle(tester);
    expect(title, findsNothing);

    ProWelcome.ready();
    await settle(tester);
    expect(title, findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ProWelcome.prefsKey), isTrue);

    await tester.tap(find.byKey(const ValueKey('proWelcomeLater')));
    await tester.pumpAndSettle();
    await ProWelcome.maybeShow();
    await settle(tester);
    expect(title, findsNothing);
  });

  testWidgets('waits for an open paywall to close', (tester) async {
    await host(tester);
    ProWelcome.ready();
    ProWelcome.hold();
    ProService.instance.active.value = true;
    await ProWelcome.maybeShow();
    await settle(tester);
    expect(title, findsNothing);

    ProWelcome.release();
    await settle(tester);
    expect(title, findsOneWidget);
  });

  testWidgets('nothing without Pro', (tester) async {
    await host(tester);
    ProWelcome.ready();
    await settle(tester);

    expect(title, findsNothing);
  });

  testWidgets('Pro older than a day is marked welcomed without the dialog', (
    tester,
  ) async {
    await host(tester);
    ProService.instance.since.value = DateTime.now().subtract(
      const Duration(days: 2),
    );
    ProService.instance.active.value = true;
    ProWelcome.ready();
    await settle(tester);

    expect(title, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ProWelcome.prefsKey), isTrue);
  });

  testWidgets('without the store saying when Pro began, it waits', (
    tester,
  ) async {
    await host(tester);
    ProService.instance.since.value = null;
    ProService.instance.active.value = true;
    ProWelcome.ready();
    await settle(tester);

    expect(title, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ProWelcome.prefsKey), isNull);
  });
}

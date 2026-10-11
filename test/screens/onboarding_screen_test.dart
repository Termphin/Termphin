import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/onboarding_screen.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/app/onboarding_service.dart';

import '../support/test_app.dart';

void main() {
  const analyticsChannel = MethodChannel('posthog_flutter');
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
  });

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    void Function(ServerAnswer)? onComplete,
  }) async {
    await pumpTestApp(
      tester,
      OnboardingScreen(onComplete: (r) => onComplete?.call(r.answer)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> skipToAnalytics(WidgetTester tester) async {
    await tapAndSettle(tester, t.onboarding.getStarted);
    expect(find.text(t.onboarding.serverTitle), findsOneWidget);
    await tapAndSettle(tester, t.onboarding.serverYes);
    await tapAndSettle(tester, t.onboarding.continueAction);
    expect(find.text(t.onboarding.permissionsTitle), findsOneWidget);
    await tapAndSettle(tester, t.onboarding.continueAction);
    expect(find.text(t.analyticsConsent.title), findsOneWidget);
  }

  testWidgets(
    'the analytics box is checked by default, so finishing shares analytics',
    (tester) async {
      ServerAnswer? answer;
      await pumpOnboarding(tester, onComplete: (a) => answer = a);

      expect(find.text(t.onboarding.welcomeTitle), findsOneWidget);
      await skipToAnalytics(tester);
      await tapAndSettle(tester, t.onboarding.finish);

      expect(answer, ServerAnswer.hasServer);
      expect(await OnboardingService.instance.isCompleted(), isTrue);
      expect(await AnalyticsService.instance.loadConsent(), isTrue);
    },
  );

  testWidgets(
    'unchecking the analytics box before finishing declines analytics',
    (tester) async {
      await pumpOnboarding(tester);

      await skipToAnalytics(tester);
      await tapAndSettle(tester, t.analyticsConsent.checkboxLabel);
      await tapAndSettle(tester, t.onboarding.finish);

      expect(await OnboardingService.instance.isCompleted(), isTrue);
      expect(await AnalyticsService.instance.loadConsent(), isFalse);
    },
  );

  testWidgets('the server question has to be answered to go on', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await tapAndSettle(tester, t.onboarding.getStarted);

    await tapAndSettle(tester, t.onboarding.continueAction);
    expect(find.text(t.onboarding.serverTitle), findsOneWidget);

    await tapAndSettle(tester, t.onboarding.serverNotYet);
    await tapAndSettle(tester, t.onboarding.continueAction);
    expect(find.text(t.onboarding.permissionsTitle), findsOneWidget);
  });

  testWidgets('answering not yet shows where a server comes from', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await tapAndSettle(tester, t.onboarding.getStarted);
    expect(find.text(t.serverGuide.cloudTitle), findsNothing);

    await tapAndSettle(tester, t.onboarding.serverNotYet);

    expect(find.text(t.serverGuide.computerTitle), findsOneWidget);
    expect(find.text(t.serverGuide.cloudTitle), findsOneWidget);
  });

  testWidgets(
    'the permissions page offers system grants rather than switches',
    (tester) async {
      await pumpOnboarding(tester);
      await tapAndSettle(tester, t.onboarding.getStarted);
      await tapAndSettle(tester, t.onboarding.serverYes);
      await tapAndSettle(tester, t.onboarding.continueAction);

      expect(find.text(t.onboarding.backgroundTitle), findsOneWidget);
      expect(find.text(t.common.allow), findsOneWidget);
      expect(find.text(t.common.allowed), findsOneWidget);

      await tapAndSettle(tester, t.onboarding.backgroundTitle);

      expect(find.text(t.onboarding.permissionsTitle), findsOneWidget);
    },
  );

  testWidgets('back button returns to the previous page', (tester) async {
    await pumpOnboarding(tester);

    await tapAndSettle(tester, t.onboarding.getStarted);
    expect(find.text(t.onboarding.serverTitle), findsOneWidget);

    await tapAndSettle(tester, t.onboarding.back);

    expect(find.text(t.onboarding.welcomeTitle), findsOneWidget);
  });
}

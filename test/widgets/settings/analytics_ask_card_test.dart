import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/main_shell.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/app/review_prompt_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/analytics_recorder.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  final service = AnalyticsService.instance;
  final today = DateTime(2026, 11, 17, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      kReviewSuccessfulConnectionsPrefsKey: 3,
      kReviewFirstConnectionAtPrefsKey: today
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch,
    });
    service.resetForTest();
    analyticsRecorder.clear();
    AnalyticsService.now = () => today;
  });

  tearDown(() {
    service.resetForTest();
    AnalyticsService.now = DateTime.now;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpShell(WidgetTester tester) async {
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    addTearDown(manager.dispose);
    final container = ProviderContainer.test(
      overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
    );
    await pumpTestApp(tester, const MainShell(), container: container);
    await settle(tester);
  }

  testWidgets('the home screen shows no question until it is asked', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.text(t.analyticsConsent.askTitle), findsNothing);
  });

  testWidgets('Sure shares, and the card goes away', (tester) async {
    await pumpShell(tester);
    await tester.runAsync(service.maybeAsk);
    await settle(tester);
    expect(find.text(t.analyticsConsent.askTitle), findsOneWidget);

    await tester.tap(find.text(t.analyticsConsent.askYes));
    await settle(tester);

    expect(find.text(t.analyticsConsent.askTitle), findsNothing);
    expect(await tester.runAsync(service.loadConsent), isTrue);
  });

  testWidgets('No thanks declines, and the card goes away', (tester) async {
    await pumpShell(tester);
    await tester.runAsync(service.maybeAsk);
    await settle(tester);

    await tester.tap(find.text(t.analyticsConsent.askNo));
    await settle(tester);

    expect(find.text(t.analyticsConsent.askTitle), findsNothing);
    expect(await tester.runAsync(service.loadConsent), isFalse);
  });

  testWidgets('leaving the home screen unanswered is a no, never asked again', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.runAsync(service.maybeAsk);
    await settle(tester);

    await tester.tap(find.text(t.nav.settings).last);
    await settle(tester);
    await tester.tap(find.text(t.nav.home).last);
    await settle(tester);

    expect(find.text(t.analyticsConsent.askTitle), findsNothing);
    expect(await tester.runAsync(service.loadConsent), isNull);
    expect(await tester.runAsync(service.maybeAsk), isFalse);
  });
}

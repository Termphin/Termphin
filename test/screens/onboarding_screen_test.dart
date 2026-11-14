import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/sync_provider.dart';
import 'package:termphin/screens/onboarding_screen.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/app/onboarding_service.dart';
import 'package:termphin/services/sync/sync_coordinator.dart';
import 'package:termphin/services/sync/sync_engine.dart';
import 'package:termphin/services/sync/sync_service.dart';

import '../support/sync_fakes.dart';
import '../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    void Function(ServerAnswer)? onComplete,
  }) async {
    await pumpTestApp(
      tester,
      OnboardingScreen(onComplete: onComplete ?? (_) {}),
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

  group('returning user', () {
    Future<void> pumpReturning(
      WidgetTester tester, {
      required SyncState state,
      Future<SyncReport> Function(String passphrase)? unlock,
      void Function(ServerAnswer)? onComplete,
    }) async {
      final service = SyncService(
        cloud: FakeSyncCloud(),
        vault: FakeSyncVault(),
        local: FakeSyncLocal(),
        uid: () => 'u1',
      );
      final container = ProviderContainer(
        overrides: [
          syncCoordinatorProvider.overrideWithValue(
            SyncCoordinator(service: service, reload: () async {}),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pumpTestApp(
        tester,
        OnboardingScreen(
          onComplete: onComplete ?? (_) {},
          accountsAvailable: true,
          signIn: (_) async => true,
          syncState: () async => state,
          unlock: unlock ?? (_) async => const SyncReport(),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
    }

    Future<void> enterPassphrase(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextFormField), text);
      await tester.pump();
    }

    testWidgets('the sign-in link is hidden when accounts are unavailable', (
      tester,
    ) async {
      await pumpTestApp(
        tester,
        OnboardingScreen(onComplete: (_) {}, accountsAvailable: false),
      );
      await tester.pumpAndSettle();

      expect(find.text(t.onboarding.signInLink), findsNothing);
    });

    testWidgets('the sign-in link is shown when accounts are available', (
      tester,
    ) async {
      await pumpTestApp(
        tester,
        OnboardingScreen(onComplete: (_) {}, accountsAvailable: true),
      );
      await tester.pumpAndSettle();

      expect(find.text(t.onboarding.signInLink), findsOneWidget);
    });

    testWidgets(
      'signing in to a locked sync asks for the passphrase instead of a server',
      (tester) async {
        ServerAnswer? answer;
        await pumpReturning(
          tester,
          state: SyncState.locked,
          unlock: (passphrase) async {
            if (passphrase != 'right') {
              throw const SyncException(SyncFailure.wrongPassphrase);
            }
            return const SyncReport();
          },
          onComplete: (a) => answer = a,
        );

        await tapAndSettle(tester, t.onboarding.signInLink);
        await tapAndSettle(tester, t.onboarding.getStarted);

        expect(find.text(t.onboarding.unlockTitle), findsOneWidget);
        expect(find.text(t.onboarding.serverTitle), findsNothing);

        await enterPassphrase(tester, 'wrong');
        await tapAndSettle(tester, t.onboarding.unlockAction);
        expect(
          find.text(t.account.sync.failure.wrongPassphrase),
          findsOneWidget,
        );
        expect(find.text(t.onboarding.permissionsTitle), findsNothing);

        await enterPassphrase(tester, 'right');
        await tapAndSettle(tester, t.onboarding.unlockAction);
        expect(find.text(t.onboarding.permissionsTitle), findsOneWidget);

        await tapAndSettle(tester, t.onboarding.continueAction);
        expect(find.text(t.analyticsConsent.title), findsOneWidget);
        await tapAndSettle(tester, t.onboarding.finish);

        expect(answer, ServerAnswer.synced);
        expect(await OnboardingService.instance.isCompleted(), isTrue);
      },
    );

    testWidgets('not now goes back to the server question', (tester) async {
      await pumpReturning(tester, state: SyncState.locked);

      await tapAndSettle(tester, t.onboarding.signInLink);
      await tapAndSettle(tester, t.onboarding.getStarted);
      expect(find.text(t.onboarding.unlockTitle), findsOneWidget);

      await tapAndSettle(tester, t.onboarding.notNow);

      expect(find.text(t.onboarding.serverTitle), findsOneWidget);
      expect(find.text(t.onboarding.unlockTitle), findsNothing);
    });

    testWidgets(
      'with sync off after signing in, the server question is asked',
      (tester) async {
        ServerAnswer? answer;
        await pumpReturning(
          tester,
          state: SyncState.notSetUp,
          onComplete: (a) => answer = a,
        );

        await tapAndSettle(tester, t.onboarding.signInLink);
        await tapAndSettle(tester, t.onboarding.getStarted);

        expect(find.text(t.onboarding.serverTitle), findsOneWidget);
        expect(find.text(t.onboarding.unlockTitle), findsNothing);

        await tapAndSettle(tester, t.onboarding.serverYes);
        await tapAndSettle(tester, t.onboarding.continueAction);
        await tapAndSettle(tester, t.onboarding.continueAction);
        await tapAndSettle(tester, t.onboarding.finish);

        expect(answer, ServerAnswer.hasServer);
      },
    );

    testWidgets('with sync already unlocked, the server question is skipped', (
      tester,
    ) async {
      ServerAnswer? answer;
      await pumpReturning(
        tester,
        state: SyncState.ready,
        onComplete: (a) => answer = a,
      );

      await tapAndSettle(tester, t.onboarding.signInLink);
      await tapAndSettle(tester, t.onboarding.getStarted);

      expect(find.text(t.onboarding.serverTitle), findsNothing);
      expect(find.text(t.onboarding.unlockTitle), findsNothing);
      expect(find.text(t.onboarding.permissionsTitle), findsOneWidget);

      await tapAndSettle(tester, t.onboarding.continueAction);
      await tapAndSettle(tester, t.onboarding.finish);

      expect(answer, ServerAnswer.synced);
    });
  });
}

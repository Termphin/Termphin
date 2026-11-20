import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/app/review_prompt_service.dart';

import '../../support/analytics_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = AnalyticsService.instance;
  final today = DateTime(2026, 11, 17, 12);

  /// Prefs for someone who has connected [connections] times, the first
  /// time [daysAgo] days before [today], and has answered nothing yet.
  Map<String, Object> used({int connections = 3, int daysAgo = 2}) => {
    kReviewSuccessfulConnectionsPrefsKey: connections,
    kReviewFirstConnectionAtPrefsKey: today
        .subtract(Duration(days: daysAgo))
        .millisecondsSinceEpoch,
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.resetForTest();
    analyticsRecorder.clear();
  });

  tearDown(() {
    AnalyticsService.firebaseUpOverride = null;
    AnalyticsService.startOverride = null;
  });

  group('the one-time question', () {
    test('is not asked before three connections', () async {
      SharedPreferences.setMockInitialValues(used(connections: 2));

      expect(await service.maybeAsk(), isFalse);
      expect(service.asking.value, isFalse);
    });

    test('is asked after a few connections, even on the first day', () async {
      SharedPreferences.setMockInitialValues(used(daysAgo: 0));

      expect(await service.maybeAsk(), isTrue);
    });

    test('is asked once the app has been used for real', () async {
      SharedPreferences.setMockInitialValues(used());

      expect(await service.maybeAsk(), isTrue);
      expect(service.asking.value, isTrue);
    });

    test('is asked only once in the app\'s life, even unanswered', () async {
      SharedPreferences.setMockInitialValues(used());

      expect(await service.maybeAsk(), isTrue);
      service.dismissAsk();

      expect(await service.maybeAsk(), isFalse);
      expect(service.asking.value, isFalse);
    });

    test('left unanswered collects nothing', () async {
      SharedPreferences.setMockInitialValues(used());
      await service.maybeAsk();
      service.dismissAsk();
      await service.init();

      await service.capture(AnalyticsEvent.appOpened);

      expect(await service.loadConsent(), isNull);
      expect(analyticsRecorder.events, isEmpty);
    });

    test('is not asked of someone who already answered in Settings', () async {
      SharedPreferences.setMockInitialValues(used());
      await service.setConsent(false);

      expect(await service.maybeAsk(), isFalse);
    });

    test('answered takes the card down and records the answer', () async {
      SharedPreferences.setMockInitialValues(used());
      await service.maybeAsk();

      await service.setConsent(true);

      expect(service.asking.value, isFalse);
      expect(await service.loadConsent(), isTrue);
      expect(await service.maybeAsk(), isFalse);
    });
  });

  group('a yes from the old onboarding', () {
    test('is dropped, because its box came ticked', () async {
      SharedPreferences.setMockInitialValues({kAnalyticsConsentPrefsKey: true});

      expect(await service.loadConsent(), isNull);
    });

    test('dropped, leaves the user to be asked once', () async {
      SharedPreferences.setMockInitialValues({
        kAnalyticsConsentPrefsKey: true,
        ...used(),
      });

      expect(await service.maybeAsk(), isTrue);
    });

    test('a no from the old onboarding stays a no', () async {
      SharedPreferences.setMockInitialValues({
        kAnalyticsConsentPrefsKey: false,
      });

      expect(await service.loadConsent(), isFalse);
    });

    test('a yes given after the change is kept', () async {
      await service.setConsent(true);

      expect(await service.loadConsent(), isTrue);
    });
  });

  test('declining does not start Firebase when nothing else has', () async {
    var starts = 0;
    AnalyticsService.firebaseUpOverride = () => false;
    AnalyticsService.startOverride = () async {
      starts++;
      return true;
    };

    await service.setConsent(false);

    expect(starts, 0);
    expect(analyticsRecorder.calls, isEmpty);
    expect(await service.loadConsent(), isFalse);
  });

  test('declining switches collection off when Firebase is up', () async {
    AnalyticsService.firebaseUpOverride = () => true;

    await service.setConsent(false);

    expect(analyticsRecorder.calls, ['disable']);
  });
}

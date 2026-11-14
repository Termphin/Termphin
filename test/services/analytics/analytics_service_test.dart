import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/analytics/analytics_service.dart';

import '../../support/analytics_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = analyticsRecorder.calls;

  Map<String, Object?> lastEvent() {
    final event = analyticsRecorder.events.last;
    return {'eventName': event.name, 'properties': event.parameters};
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AnalyticsService.instance.resetForTest();
    analyticsRecorder.clear();
  });

  test('the SDK is not touched before the prompt has been answered', () async {
    expect(await AnalyticsService.instance.loadConsent(), isNull);

    await AnalyticsService.instance.init();

    expect(calls, isEmpty);
  });

  test('an event captured before consent goes nowhere', () async {
    await AnalyticsService.instance.init();

    await AnalyticsService.instance.capture(AnalyticsEvent.appOpened);

    expect(analyticsRecorder.events, isEmpty);
  });

  test('granting consent switches collection on', () async {
    await AnalyticsService.instance.init();
    calls.clear();

    await AnalyticsService.instance.setConsent(true);

    expect(await AnalyticsService.instance.loadConsent(), isTrue);
    expect(calls, ['enable']);
  });

  test('withdrawing consent persists it and switches collection off', () async {
    await AnalyticsService.instance.setConsent(true);
    calls.clear();

    await AnalyticsService.instance.setConsent(false);

    expect(await AnalyticsService.instance.loadConsent(), isFalse);
    expect(calls, contains('disable'));
    expect(calls, isNot(contains('enable')));
  });

  test('a previously granted consent switches collection on at the next '
      'launch', () async {
    SharedPreferences.setMockInitialValues({kAnalyticsConsentPrefsKey: true});
    AnalyticsService.instance.resetForTest();
    calls.clear();

    await AnalyticsService.instance.init();

    expect(calls, ['enable']);
  });

  test('a previously denied consent leaves Firebase alone at the next '
      'launch', () async {
    SharedPreferences.setMockInitialValues({kAnalyticsConsentPrefsKey: false});
    AnalyticsService.instance.resetForTest();
    calls.clear();

    await AnalyticsService.instance.init();
    await AnalyticsService.instance.capture(AnalyticsEvent.appOpened);

    expect(calls, isEmpty);
  });

  group('properties', () {
    setUp(() => AnalyticsService.instance.setConsent(true));

    test('go out under their declared names, a flag spelled out', () async {
      await AnalyticsService.instance.capture(
        AnalyticsEvent.connectionFailed,
        properties: const {
          AnalyticsProperty.reason: 'auth_failed',
          AnalyticsProperty.viaJumpHost: true,
          AnalyticsProperty.fallbackCount: 2,
        },
      );

      expect(lastEvent()['eventName'], 'connection_failed');
      expect(lastEvent()['properties'], {
        'reason': 'auth_failed',
        'via_jump_host': 'true',
        'fallback_count': 2,
      });
    });

    test('a screen view names the screen, not the widget class', () async {
      await AnalyticsService.instance.screen(AnalyticsScreen.knownHosts);

      expect(lastEvent()['eventName'], 'screen_viewed');
      expect(lastEvent()['properties'], {'screen': 'known_hosts'});
    });

    test(
      'a setting with no scalar value reports only which one it was',
      () async {
        await AnalyticsService.instance.settingChanged('toolbar_order', null);

        expect(lastEvent()['properties'], {'setting': 'toolbar_order'});
      },
    );

    test('a label with spaces is still a legal value', () async {
      await expectLater(
        AnalyticsService.instance.settingChanged(
          'terminal_font_family',
          'JetBrains Mono',
        ),
        completes,
      );
      expect(lastEvent()['properties'], {
        'setting': 'terminal_font_family',
        'value': 'JetBrains Mono',
      });
    });

    test('an address, a path or an account trips the assertion', () {
      for (final leak in const [
        'user@example.com',
        '/home/me/.ssh/id_ed25519',
        r'C:\Users\me',
        'line one\nline two',
      ]) {
        expect(
          () => AnalyticsService.instance.capture(
            AnalyticsEvent.connectionFailed,
            properties: {AnalyticsProperty.value: leak},
          ),
          throwsA(isA<AssertionError>()),
          reason: leak,
        );
      }
    });
  });

  group('crash reports', () {
    test('go nowhere before consent', () async {
      await AnalyticsService.instance.recordError(StateError('boom'), null);

      expect(analyticsRecorder.errors, isEmpty);
    });

    test('go once consent is on', () async {
      await AnalyticsService.instance.setConsent(true);

      await AnalyticsService.instance.recordError(StateError('boom'), null);

      expect(analyticsRecorder.errors, [isA<StateError>()]);
    });

    test('a transport closing is not one, and names the machine', () async {
      await AnalyticsService.instance.setConsent(true);

      await AnalyticsService.instance.recordError(
        const SocketException('Connection reset', port: 22),
        null,
      );

      expect(analyticsRecorder.errors, isEmpty);
    });
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/analytics/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final calls = <String>[];
  final arguments = <String, dynamic>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AnalyticsService.instance.resetForTest();
    calls.clear();
    arguments.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'setup') {
            arguments['optOut'] = (call.arguments as Map)['optOut'];
          }
          if (call.method == 'capture') {
            final map = call.arguments as Map;
            arguments['eventName'] = map['eventName'];
            arguments['properties'] = map['properties'];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('the SDK is not touched before the prompt has been answered', () async {
    expect(await AnalyticsService.instance.loadConsent(), isNull);

    await AnalyticsService.instance.init();

    expect(calls, isEmpty);
  });

  test('an event captured before consent goes nowhere', () async {
    await AnalyticsService.instance.init();

    await AnalyticsService.instance.capture(AnalyticsEvent.appOpened);

    expect(calls, isNot(contains('capture')));
  });

  test('granting consent starts the SDK and enables capture', () async {
    await AnalyticsService.instance.init();
    calls.clear();

    await AnalyticsService.instance.setConsent(true);

    expect(await AnalyticsService.instance.loadConsent(), isTrue);
    expect(calls, containsAllInOrder(['setup', 'enable']));
    expect(calls, isNot(contains('disable')));
  });

  test('withdrawing consent persists it and disables capture', () async {
    await AnalyticsService.instance.setConsent(true);
    calls.clear();

    await AnalyticsService.instance.setConsent(false);

    expect(await AnalyticsService.instance.loadConsent(), isFalse);
    expect(calls, contains('disable'));
    expect(calls, isNot(contains('enable')));
  });

  test('a previously granted consent starts the SDK on the next run', () async {
    SharedPreferences.setMockInitialValues({kAnalyticsConsentPrefsKey: true});
    AnalyticsService.instance.resetForTest();
    calls.clear();

    await AnalyticsService.instance.init();

    expect(calls, contains('setup'));
  });

  test(
    'a previously denied consent leaves the SDK alone on the next run',
    () async {
      SharedPreferences.setMockInitialValues({
        kAnalyticsConsentPrefsKey: false,
      });
      AnalyticsService.instance.resetForTest();
      calls.clear();

      await AnalyticsService.instance.init();

      expect(calls, isEmpty);
    },
  );

  group('properties', () {
    setUp(() => AnalyticsService.instance.setConsent(true));

    test('go out under their declared names', () async {
      await AnalyticsService.instance.capture(
        AnalyticsEvent.connectionFailed,
        properties: const {
          AnalyticsProperty.reason: 'auth_failed',
          AnalyticsProperty.viaJumpHost: true,
          AnalyticsProperty.fallbackCount: 2,
        },
      );

      expect(arguments['eventName'], 'connection_failed');
      expect(arguments['properties'], {
        'reason': 'auth_failed',
        'via_jump_host': true,
        'fallback_count': 2,
      });
    });

    test('a screen view names the screen, not the widget class', () async {
      await AnalyticsService.instance.screen(AnalyticsScreen.knownHosts);

      expect(arguments['eventName'], 'screen_viewed');
      expect(arguments['properties'], {'screen': 'known_hosts'});
    });

    test(
      'a setting with no scalar value reports only which one it was',
      () async {
        await AnalyticsService.instance.settingChanged('toolbar_order', null);

        expect(arguments['properties'], {'setting': 'toolbar_order'});
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
      expect(arguments['properties'], {
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

  group('isTransportOnlyException', () {
    test('drops a single SocketException entry matched by type', () {
      final properties = {
        r'$exception_list': [
          {'type': 'SocketException', 'value': 'Connection refused'},
        ],
      };

      expect(isTransportOnlyException(properties), isTrue);
    });

    test(
      'drops a single entry matched only by value starting with SocketException',
      () {
        final properties = {
          r'$exception_list': [
            {
              'type': 'OSClientError',
              'value':
                  'SocketException: Software caused connection abort, address = devbox, port = 36328',
            },
          ],
        };

        expect(isTransportOnlyException(properties), isTrue);
      },
    );

    test('keeps a list mixing a SocketException with a StateError', () {
      final properties = {
        r'$exception_list': [
          {'type': 'SocketException', 'value': 'Connection reset'},
          {'type': 'StateError', 'value': 'Bad state: closed'},
        ],
      };

      expect(isTransportOnlyException(properties), isFalse);
    });

    test('keeps an empty list', () {
      final properties = {r'$exception_list': <Map<String, Object?>>[]};

      expect(isTransportOnlyException(properties), isFalse);
    });

    test('keeps a missing exception list key', () {
      final properties = <String, Object?>{};

      expect(isTransportOnlyException(properties), isFalse);
    });

    test(
      'keeps exception list holding something other than a list of maps without throwing',
      () {
        for (final malformed in [
          'not a list',
          42,
          [1, 2, 3],
          ['string entry'],
          [null],
        ]) {
          expect(
            isTransportOnlyException({r'$exception_list': malformed}),
            isFalse,
          );
        }
      },
    );
  });
}

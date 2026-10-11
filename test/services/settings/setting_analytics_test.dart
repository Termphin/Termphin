import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/settings/setting.dart';

enum _Mode { compact, roomy }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const analyticsChannel = MethodChannel('posthog_flutter');
  final captured = <Map<String, Object?>>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async {
          if (call.method == 'capture') {
            final arguments = call.arguments as Map;
            captured.add({
              'event': arguments['eventName'],
              ...?(arguments['properties'] as Map?)?.cast<String, Object?>(),
            });
          }
          return null;
        });
    AnalyticsService.instance.resetForTest();
    await AnalyticsService.instance.setConsent(true);
    captured.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
  });

  test('scalars report their value', () {
    expect(Setting.boolean('a', fallback: false).analyticsValue, isFalse);
    expect(Setting.integer('b', fallback: 7).analyticsValue, 7);
    expect(Setting.text('c', fallback: 'block').analyticsValue, 'block');
    expect(
      Setting.option(
        'd',
        fallback: _Mode.roomy,
        values: _Mode.values,
      ).analyticsValue,
      'roomy',
    );
  });

  test('a list reports its size and never its entries', () {
    final custom = Setting.textList(
      'toolbar_custom_keys',
      fallback: const [r'[1;5A', r'[1;5B'],
    );
    expect(custom.analyticsValue, 2);
  });

  test('describe overrides what a compound value reports', () {
    final grid = Setting<({int columns, int rows})>(
      key: 'grid',
      fallback: (columns: 4, rows: 2),
      read: (_) => (columns: 4, rows: 2),
      write: (_, _) async {},
      describe: (value) => '${value.columns}x${value.rows}',
    );
    expect(grid.analyticsValue, '4x2');
  });

  test(
    'a value with no scalar reading reports nothing rather than guessing',
    () {
      final opaque = Setting<Object>(
        key: 'opaque',
        fallback: Object(),
        read: (_) => Object(),
        write: (_, _) async {},
      );
      expect(opaque.analyticsValue, isNull);
    },
  );

  test('an untracked setting still persists and broadcasts', () async {
    final position = Setting.number('dock_position', fallback: 0, track: false);
    await position.set(0.75);
    await pumpEventQueue();

    expect(position.track, isFalse);
    expect(position.value, 0.75);
    expect(
      (await SharedPreferences.getInstance()).getDouble('dock_position'),
      0.75,
    );
    expect(captured, isEmpty);
  });

  group('a write reports itself', () {
    test('without the settings screen having to remember to', () async {
      final fontSize = Setting.number('terminal_font_size', fallback: 13);

      await fontSize.set(15);
      await pumpEventQueue();

      expect(captured, [
        {
          'event': 'setting_changed',
          'setting': 'terminal_font_size',
          'value': 15.0,
        },
      ]);
    });

    test('naming the setting even when the value cannot be reduced', () async {
      final opaque = Setting<Object>(
        key: 'opaque',
        fallback: Object(),
        read: (_) => Object(),
        write: (_, _) async {},
      );

      await opaque.set(Object());
      await pumpEventQueue();

      expect(captured, [
        {'event': 'setting_changed', 'setting': 'opaque'},
      ]);
    });

    test('with a count, never the entries themselves', () async {
      final custom = Setting.textList('toolbar_custom_keys');

      await custom.set(const [r'\e[1;5A', r'\e[1;5B', r'\e[1;5C']);
      await pumpEventQueue();

      expect(captured, [
        {
          'event': 'setting_changed',
          'setting': 'toolbar_custom_keys',
          'value': 3,
        },
      ]);
    });

    test('loading from disk is not a change and reports nothing', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final theme = Setting.text('theme_mode', fallback: 'system');

      await theme.load();
      await pumpEventQueue();

      expect(theme.value, 'dark');
      expect(captured, isEmpty);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/providers/theme_provider.dart';
import 'package:termphin/services/settings/theme_settings.dart';
import 'package:termphin/theme/theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('falls back to the device setting for a missing value', () async {
    expect(await themeModeSetting.load(), AppThemeMode.system);
  });

  test(
    'falls back to the device setting for a value it does not know',
    () async {
      SharedPreferences.setMockInitialValues({kThemeModePrefsKey: 'sepia'});
      expect(await themeModeSetting.load(), AppThemeMode.system);
    },
  );

  test('saves the choice', () async {
    await themeModeSetting.set(AppThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kThemeModePrefsKey), 'light');
    expect(await themeModeSetting.load(), AppThemeMode.light);
  });

  test(
    'the provider starts from the value preloaded before the first frame',
    () async {
      SharedPreferences.setMockInitialValues({kThemeModePrefsKey: 'dark'});
      await themeModeSetting.load();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), AppThemeMode.dark);

      await container
          .read(themeModeProvider.notifier)
          .setMode(AppThemeMode.light);
      expect(container.read(themeModeProvider), AppThemeMode.light);
      expect(await themeModeSetting.load(), AppThemeMode.light);
    },
  );

  test('each theme carries the palette widgets read off the context', () {
    expect(AppTheme.lightTheme.extension<AppColors>(), same(AppColors.light));
    expect(AppTheme.darkTheme.extension<AppColors>(), same(AppColors.dark));
    expect(AppTheme.lightTheme.brightness, Brightness.light);
    expect(AppColors.light.isDark, isFalse);
  });

  testWidgets('the palette follows the theme in force', (tester) async {
    late AppColors seen;
    Widget probe(ThemeData theme) => MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          seen = context.colors;
          return const SizedBox.shrink();
        },
      ),
    );

    await tester.pumpWidget(probe(AppTheme.darkTheme));
    expect(seen, same(AppColors.dark));

    await tester.pumpWidget(probe(AppTheme.lightTheme));
    await tester.pumpAndSettle();
    expect(seen.brightness, Brightness.light);
  });
}

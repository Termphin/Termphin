import 'package:flutter/material.dart';

import 'setting.dart';

const kThemeModePrefsKey = 'theme_mode';

/// Which of the two palettes the interface uses, or a deferral to Android's
/// own light/dark setting - the default, so the app matches the rest of the
/// phone until someone says otherwise.
enum AppThemeMode {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const AppThemeMode(this.themeMode);

  final ThemeMode themeMode;
}

/// Read before `runApp`, so a light-theme user never sees a dark first frame.
final Setting<AppThemeMode> themeModeSetting = Setting.option(
  kThemeModePrefsKey,
  fallback: AppThemeMode.system,
  values: AppThemeMode.values,
);

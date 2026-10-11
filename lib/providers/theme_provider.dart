import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings/theme_settings.dart';

/// The interface palette: the device's own light/dark setting by default,
/// light or dark when the user has pinned one in Settings.
///
/// The value itself lives in [themeModeSetting]; this republishes it as a
/// provider so a widget can watch it without the setting having to know
/// Riverpod exists. `loadAppSettings()` runs before `runApp`, which is why
/// there is nothing to await here and no window where the app is painted in
/// the wrong palette first.
class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    void publish() => state = themeModeSetting.value;
    themeModeSetting.addListener(publish);
    ref.onDispose(() => themeModeSetting.removeListener(publish));
    return themeModeSetting.value;
  }

  Future<void> setMode(AppThemeMode mode) => themeModeSetting.set(mode);
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);

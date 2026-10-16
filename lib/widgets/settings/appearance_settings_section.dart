import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/strings.g.dart';
import '../../providers/theme_provider.dart';
import '../../services/settings/theme_settings.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_controls.dart';

/// Appearance section: the app's light/dark/system theme mode.
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final themeModeLabels = {
      AppThemeMode.system: t.settings.themeModeSystem,
      AppThemeMode.light: t.settings.themeModeLight,
      AppThemeMode.dark: t.settings.themeModeDark,
    };
    final mode = ref.watch(themeModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.appearance),
        const SizedBox(height: AppTheme.space10),
        AppCard(
          padding: const EdgeInsets.all(AppTheme.space14),
          child: SettingsDropdownField<AppThemeMode>(
            label: t.settings.themeMode,
            value: mode,
            labels: themeModeLabels,
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../providers/theme_provider.dart';
import '../../services/settings/theme_settings.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/segmented_switch.dart';

/// Appearance section: the app's light/dark/system theme mode, as a
/// segmented switch - three short choices read at a glance, where a
/// dropdown hid two of them behind a tap.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.settings.themeMode,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppTheme.space10),
              SegmentedSwitch<AppThemeMode>(
                segments: [
                  for (final entry in themeModeLabels.entries)
                    SwitchSegment(value: entry.key, label: entry.value),
                ],
                selected: mode,
                onChanged: (v) =>
                    ref.read(themeModeProvider.notifier).setMode(v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

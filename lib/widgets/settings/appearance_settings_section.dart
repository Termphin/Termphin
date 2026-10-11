import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/theme_provider.dart';
import '../../services/settings/theme_settings.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_dropdown.dart';
import '../ui/section_header.dart';

/// Appearance section: the app's light/dark/system theme mode.
class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final themeModeLabels = {
      AppThemeMode.system: t.settings.themeModeSystem,
      AppThemeMode.light: t.settings.themeModeLight,
      AppThemeMode.dark: t.settings.themeModeDark,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.appearance),
        const SizedBox(height: 10),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.settings.themeMode,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _ThemeModeDropdown(labels: themeModeLabels),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The one setting that has to reach the app root, so it reads and writes the
/// provider directly instead of the screen's local state.
class _ThemeModeDropdown extends ConsumerWidget {
  const _ThemeModeDropdown({required this.labels});

  final Map<AppThemeMode, String> labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return DropdownButton2<AppThemeMode>(
      valueListenable: ValueNotifier(mode),
      isExpanded: true,
      underline: const SizedBox.shrink(),
      selectedItemBuilder: (context) {
        return labels.values
            .map(
              (label) => Text(
                label,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
            .toList();
      },
      onChanged: (v) {
        if (v == null) return;
        ref.read(themeModeProvider.notifier).setMode(v);
      },
      buttonStyleData: ButtonStyleData(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.fieldFill,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: context.colors.surfaceBorder),
        ),
        elevation: 0,
      ),
      iconStyleData: IconStyleData(
        icon: Icon(
          PhosphorIconsFill.caretDown,
          size: 16,
          color: context.colors.textTertiary,
        ),
        iconSize: 16,
      ),
      dropdownStyleData: appDropdownStyle(context),
      menuItemStyleData: appDropdownItemStyle(
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      items: labels.entries.map((e) {
        return DropdownItem<AppThemeMode>(
          value: e.key,
          intrinsicHeight: true,
          child: AppDropdownItem(label: e.value, selected: e.key == mode),
        );
      }).toList(),
    );
  }
}

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/action_dock_settings_screen.dart';
import '../../screens/settings/toolbar_profiles_screen.dart';
import '../../services/completion/command_completion.dart';
import '../../services/settings/floating_dock_settings.dart';
import '../../services/settings/tab_bar_settings.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../onboarding/whats_new_modal.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/new_badge.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Both the toolbar and the action dock live under this one section, named
/// for what they are rather than for the first of the two.
///
/// Each feature is its own switch, and the row into its editor only appears
/// under a switch that is on - there is nothing to arrange for something
/// that is not shown.
class TerminalControlsSettingsSection extends StatelessWidget {
  const TerminalControlsSettingsSection({super.key, required this.appVersion});

  /// Bare "1.9.0", for [NewBadge].
  final String? appVersion;

  /// The version the "New" badge below stops showing in.
  static const _newUntil = '1.11.0';

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.terminalControls),
        const SizedBox(height: AppTheme.space10),
        AppCard.fields(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: toolbarSettings.enabled,
              builder: (context, enabled, _) => Column(
                children: [
                  SettingsSwitchTile(
                    key: const ValueKey('toolbarEnabledSwitch'),
                    title: t.settings.keyToolbar,
                    subtitle: t.settings.keyToolbarSubtitle,
                    value: enabled,
                    onChanged: (value) => toolbarSettings.enabled.set(value),
                  ),
                  if (enabled) ...[
                    const AppDivider(),
                    SettingsTile(
                      title: t.settings.toolbarLayout,
                      destination: () => const ToolbarProfilesScreen(),
                    ),
                  ],
                ],
              ),
            ),
            const AppDivider(),
            ValueListenableBuilder<bool>(
              valueListenable: floatingDockSettings.enabled,
              builder: (context, enabled, _) => Column(
                children: [
                  SettingsSwitchTile(
                    key: const ValueKey('actionDockEnabledSwitch'),
                    title: t.settings.actionDock,
                    subtitle: t.settings.actionDockSwitchSubtitle,
                    value: enabled,
                    onChanged: (value) =>
                        floatingDockSettings.enabled.set(value),
                  ),
                  if (enabled) ...[
                    const AppDivider(),
                    SettingsTile(
                      title: t.settings.actionDockLayout,
                      destination: () => const ActionDockSettingsScreen(),
                    ),
                  ],
                ],
              ),
            ),
            const AppDivider(),
            ValueListenableBuilder<TabBarPosition>(
              valueListenable: tabBarPositionSetting,
              builder: (context, position, _) => SettingsSwitchTile(
                key: const ValueKey('tabsAtBottomSwitch'),
                title: t.settings.tabsAtBottom,
                titleTrailing: NewBadge(
                  appVersion: appVersion,
                  until: _newUntil,
                ),
                subtitle: t.settings.tabsAtBottomSubtitle,
                value: position == TabBarPosition.bottom,
                onChanged: (value) => tabBarPositionSetting.set(
                  value ? TabBarPosition.bottom : TabBarPosition.top,
                ),
              ),
            ),
            const AppDivider(),
            ValueListenableBuilder<bool>(
              valueListenable: commandSuggestionsSetting,
              builder: (context, enabled, _) => SettingsSwitchTile(
                key: const ValueKey('commandSuggestionsSwitch'),
                title: t.settings.commandSuggestions,
                titleTrailing: const FeatureInfoButton(
                  key: ValueKey('commandSuggestionsInfo'),
                  explainerId: kAutocompleteExplainerId,
                ),
                subtitle: t.settings.commandSuggestionsSubtitle,
                value: enabled,
                onChanged: commandSuggestionsSetting.set,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

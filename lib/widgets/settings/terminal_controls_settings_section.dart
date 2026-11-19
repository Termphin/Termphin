import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/action_dock_settings_screen.dart';
import '../../screens/settings/toolbar_profiles_screen.dart';
import '../../services/app/app_commands.dart';
import '../../services/completion/command_completion.dart';
import '../../services/platform/desktop_tray.dart';
import '../../services/settings/desktop_settings.dart';
import '../../services/settings/floating_dock_settings.dart';
import '../../services/settings/tab_bar_settings.dart';
import '../../services/settings/terminal_settings.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../onboarding/whats_new_modal.dart';
import '../terminal/command_suggestion_popup.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/new_badge.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';
import '../window/shortcuts_dialog.dart';

/// Both the toolbar and the action dock live under this one section, named
/// for what they are rather than for the first of the two.
///
/// Each feature is its own switch, and the row into its editor only appears
/// under a switch that is on - there is nothing to arrange for something
/// that is not shown.
///
/// On a desktop the key toolbar and the tabs' position are gone - they stand
/// in for a keyboard and a thumb - so the section is named for typing, the
/// dock is the action bar over the terminal, and the shortcuts and the tray
/// join it.
class TerminalControlsSettingsSection extends StatelessWidget {
  const TerminalControlsSettingsSection({super.key, required this.appVersion});

  /// Bare "1.9.0", for [NewBadge].
  final String? appVersion;

  /// The version the "New" badge below stops showing in.
  static const _newUntil = '1.11.0';

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final touch = platformHas(PlatformFeature.touchControls);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          touch ? t.settings.terminalControls : t.settings.terminalTyping,
        ),
        const SizedBox(height: AppTheme.space10),
        AppCard.fields(
          children: [
            if (touch) ...[
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
            ],
            ValueListenableBuilder<bool>(
              valueListenable: floatingDockSettings.enabled,
              builder: (context, enabled, _) => Column(
                children: [
                  SettingsSwitchTile(
                    key: const ValueKey('actionDockEnabledSwitch'),
                    title: isDesktopPlatform
                        ? t.settings.actionBar
                        : t.settings.actionDock,
                    subtitle: isDesktopPlatform
                        ? t.settings.actionBarSwitchSubtitle
                        : t.settings.actionDockSwitchSubtitle,
                    value: enabled,
                    onChanged: (value) =>
                        floatingDockSettings.enabled.set(value),
                  ),
                  if (enabled) ...[
                    const AppDivider(),
                    SettingsTile(
                      title: isDesktopPlatform
                          ? t.settings.actionBarLayout
                          : t.settings.actionDockLayout,
                      destination: () => const ActionDockSettingsScreen(),
                    ),
                  ],
                ],
              ),
            ),
            if (touch) ...[
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
            ],
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
                below: isDesktopPlatform
                    ? const SuggestionKeys(
                        key: ValueKey('commandSuggestionsKeys'),
                      )
                    : null,
                value: enabled,
                onChanged: commandSuggestionsSetting.set,
              ),
            ),
            const AppDivider(),
            ValueListenableBuilder<bool>(
              valueListenable: terminalSettings.mouseKeyboardGuard,
              builder: (context, enabled, _) => SettingsSwitchTile(
                key: const ValueKey('mouseKeyboardGuardSwitch'),
                title: t.settings.mouseKeyboardGuard,
                subtitle: t.settings.mouseKeyboardGuardSubtitle,
                value: enabled,
                onChanged: terminalSettings.mouseKeyboardGuard.set,
              ),
            ),
            if (isDesktopPlatform) ...[
              const AppDivider(),
              SettingsTile(
                key: const ValueKey('keyboardShortcutsRow'),
                title: t.commands.showShortcuts,
                subtitle: AppCommands.shortcutLabel(AppCommand.showShortcuts),
                onTap: () => showShortcutsDialog(context),
              ),
              const AppDivider(),
              FutureBuilder<bool>(
                future: DesktopTray.instance.available,
                builder: (context, available) => ValueListenableBuilder<bool>(
                  valueListenable: closeToTraySetting,
                  builder: (context, enabled, _) {
                    final hasTray = available.data ?? true;
                    return SettingsSwitchTile(
                      key: const ValueKey('closeToTraySwitch'),
                      title: t.settings.closeToTray,
                      subtitle: hasTray
                          ? t.settings.closeToTraySubtitle
                          : t.settings.closeToTrayUnavailable,
                      value: hasTray && enabled,
                      onChanged: hasTray ? closeToTraySetting.set : null,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

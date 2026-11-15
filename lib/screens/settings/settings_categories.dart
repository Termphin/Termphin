import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../widgets/settings/about_settings_section.dart';
import '../../widgets/settings/analytics_settings_section.dart';
import '../../widgets/settings/connection_settings_section.dart';
import '../../widgets/settings/feedback_settings_section.dart';
import '../../widgets/settings/open_source_settings_section.dart';
import '../../widgets/settings/privacy_settings_section.dart';
import '../../widgets/settings/security_settings_section.dart';
import '../../widgets/settings/sftp_settings_section.dart';
import '../../widgets/settings/terminal_controls_settings_section.dart';
import '../../widgets/settings/terminal_settings_section.dart';
import 'settings_category_screen.dart';

/// The categories Settings opens onto a screen of their own, for the rows
/// that lead to them and for search, which opens the same screens at the
/// setting it found.
enum SettingsCategory {
  terminal,
  files,
  connection,
  privacy,
  help,
  about;

  String title(Translations t) => switch (this) {
    terminal => t.settings.terminal,
    files => t.settings.filesRow,
    connection => t.settings.connection,
    privacy => t.settings.privacySecurity,
    help => t.settings.helpFeedback,
    about => t.settings.aboutTermphin,
  };

  String subtitle(Translations t) => switch (this) {
    terminal => t.settings.terminalRowSubtitle,
    files => t.settings.filesRowSubtitle,
    connection => t.settings.connectionRowSubtitle,
    privacy => t.settings.privacySecurityRowSubtitle,
    help => t.settings.helpFeedbackRowSubtitle,
    about => t.settings.aboutRowSubtitle,
  };

  AnalyticsScreen get _analyticsScreen => switch (this) {
    terminal => AnalyticsScreen.terminalSettings,
    files => AnalyticsScreen.filesSettings,
    connection => AnalyticsScreen.connectionSettings,
    privacy => AnalyticsScreen.privacySettings,
    help => AnalyticsScreen.helpSettings,
    about => AnalyticsScreen.aboutSettings,
  };

  /// The sections it is made of. A section alone on its screen drops its
  /// header, which would only repeat the title.
  List<Widget> _sections({String? appVersion, String? version}) =>
      switch (this) {
        terminal => [
          const TerminalSettingsSection(header: false),
          TerminalControlsSettingsSection(appVersion: appVersion),
        ],
        files => const [SftpSettingsSection(header: false)],
        connection => const [ConnectionSettingsSection(header: false)],
        privacy => const [
          SecuritySettingsSection(),
          PrivacySettingsSection(),
          AnalyticsSettingsSection(),
        ],
        help => const [FeedbackSettingsSection(header: false)],
        about => [
          AboutSettingsSection(version: version, header: false),
          const OpenSourceSettingsSection(),
        ],
      };

  /// Its screen; [focus] is the title of a setting to scroll to and mark,
  /// when search opened it.
  Widget screen(
    Translations t, {
    String? appVersion,
    String? version,
    String? focus,
  }) => SettingsCategoryScreen(
    title: title(t),
    subtitle: subtitle(t),
    analyticsScreen: _analyticsScreen,
    focus: focus,
    sections: _sections(appVersion: appVersion, version: version),
  );
}

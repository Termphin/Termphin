import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/account/account_service.dart';
import '../../utils/platform_info.dart';
import '../backup/export_screen.dart';
import '../groups/groups_screen.dart';
import 'notifications_settings_screen.dart';
import 'settings_categories.dart';

/// One thing search in Settings can find: a setting, or a screen of them.
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    required this.place,
    this.open,
    this.keywords = '',
  });

  /// What the row it finds is called, word for word: it is also what the
  /// opened screen looks for to scroll to.
  final String title;

  /// Where it is, shown under it: the screen it is on.
  final String place;

  /// Other words someone might search for it by.
  final String keywords;

  /// The screen it is on, opened at it. `null` for one on Settings itself.
  final Widget Function()? open;

  /// Every word of [query] appears in the title, the place or the keywords,
  /// in any order and case.
  bool matches(String query) {
    final haystack = '$title $place $keywords'.toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .every(haystack.contains);
  }
}

/// Everything search in Settings can find, in the order Settings shows it.
/// A row that is not on this device - a permission the platform does not
/// have, a feature this build has no account for - is left out.
///
/// Titles are the rows' own strings, so a renamed row is still found; that
/// every entry is really on the screen it opens is pinned by a test.
List<SettingsSearchEntry> settingsSearchIndex(
  Translations t, {
  String? appVersion,
  String? version,
}) {
  final k = t.settings.searchKeywords;
  final top = t.settings.title;

  SettingsSearchEntry inCategory(
    SettingsCategory category,
    String title, {
    String keywords = '',
  }) => SettingsSearchEntry(
    title: title,
    place: category.title(t),
    keywords: keywords,
    open: () => category.screen(
      t,
      appVersion: appVersion,
      version: version,
      focus: title,
    ),
  );

  SettingsSearchEntry category(SettingsCategory category) =>
      SettingsSearchEntry(
        title: category.title(t),
        place: top,
        keywords: category.subtitle(t),
        open: () =>
            category.screen(t, appVersion: appVersion, version: version),
      );

  SettingsSearchEntry notification(String title, {String keywords = ''}) =>
      SettingsSearchEntry(
        title: title,
        place: t.settings.notificationsSection,
        keywords: keywords,
        open: () =>
            NotificationsSettingsScreen(appVersion: appVersion, focus: title),
      );

  return [
    SettingsSearchEntry(
      title: t.settings.themeMode,
      place: top,
      keywords: k.themeMode,
    ),
    SettingsSearchEntry(
      title: t.settings.notificationsSection,
      place: top,
      keywords: t.settings.notificationsRowSubtitle,
      open: () => NotificationsSettingsScreen(appVersion: appVersion),
    ),
    notification(t.settings.commandNotifications),
    notification(t.settings.noticeLines),
    notification(t.settings.openAppNotices),
    if (isAndroidPlatform || isIOSPlatform)
      notification(
        t.settings.notificationsPermission,
        keywords: k.notificationsPermission,
      ),
    if (AccountService.instance.available)
      notification(
        platformHas(PlatformFeature.receivesPush)
            ? t.settings.notifyWhenClosed
            : t.settings.notifyOnPhone,
      ),
    category(SettingsCategory.terminal),
    inCategory(
      SettingsCategory.terminal,
      t.settings.terminalAppearance,
      keywords: k.terminalAppearance,
    ),
    inCategory(
      SettingsCategory.terminal,
      t.settings.fastUpload,
      keywords: k.fastUpload,
    ),
    inCategory(
      SettingsCategory.terminal,
      t.settings.keyToolbar,
      keywords: k.keyToolbar,
    ),
    inCategory(SettingsCategory.terminal, t.settings.toolbarLayout),
    if (!isDesktopPlatform)
      inCategory(
        SettingsCategory.terminal,
        t.settings.actionDock,
        keywords: k.actionDock,
      ),
    if (!isDesktopPlatform)
      inCategory(SettingsCategory.terminal, t.settings.actionDockLayout),
    inCategory(
      SettingsCategory.terminal,
      t.settings.tabsAtBottom,
      keywords: k.tabsAtBottom,
    ),
    inCategory(
      SettingsCategory.terminal,
      t.settings.commandSuggestions,
      keywords: k.commandSuggestions,
    ),
    if (!isDesktopPlatform)
      inCategory(
        SettingsCategory.terminal,
        t.settings.mouseKeyboardGuard,
        keywords: k.mouseKeyboardGuard,
      ),
    category(SettingsCategory.files),
    inCategory(
      SettingsCategory.files,
      t.settings.downloadFolder,
      keywords: k.downloadFolder,
    ),
    inCategory(SettingsCategory.files, t.settings.sftpShowHidden),
    inCategory(SettingsCategory.files, t.settings.sftpFollowTerminal),
    inCategory(
      SettingsCategory.files,
      t.settings.textEditor,
      keywords: k.textEditor,
    ),
    category(SettingsCategory.connection),
    inCategory(
      SettingsCategory.connection,
      t.settings.remoteAgentToggle,
      keywords: k.remoteAgentToggle,
    ),
    inCategory(SettingsCategory.connection, t.settings.remoteAgentHowItWorks),
    if (isIOSPlatform)
      inCategory(SettingsCategory.connection, t.settings.backgroundSuspended),
    if (isAndroidPlatform)
      inCategory(
        SettingsCategory.connection,
        t.settings.batteryUnrestricted,
        keywords: k.batteryUnrestricted,
      ),

    SettingsSearchEntry(
      title: t.groups.title,
      place: top,
      keywords: t.settings.groupsSubtitle,
      open: () => const GroupsScreen(),
    ),
    category(SettingsCategory.privacy),
    inCategory(
      SettingsCategory.privacy,
      t.settings.pinLock,
      keywords: k.pinLock,
    ),
    inCategory(
      SettingsCategory.privacy,
      t.settings.biometricUnlock,
      keywords: k.biometricUnlock,
    ),
    inCategory(
      SettingsCategory.privacy,
      t.settings.knownHosts,
      keywords: k.knownHosts,
    ),
    inCategory(
      SettingsCategory.privacy,
      t.settings.anonymize,
      keywords: k.anonymize,
    ),
    inCategory(
      SettingsCategory.privacy,
      t.settings.analyticsToggle,
      keywords: k.analyticsToggle,
    ),
    SettingsSearchEntry(
      title: t.exportScreen.title,
      place: top,
      keywords: k.backup,
      open: () => const ExportScreen(),
    ),
    category(SettingsCategory.help),
    inCategory(
      SettingsCategory.help,
      t.settings.sendFeedback,
      keywords: k.sendFeedback,
    ),
    inCategory(
      SettingsCategory.help,
      t.settings.reportBug,
      keywords: k.reportBug,
    ),
    inCategory(SettingsCategory.help, t.settings.errorReports),
    inCategory(SettingsCategory.help, t.settings.manual),
    category(SettingsCategory.about),
    inCategory(SettingsCategory.about, t.settings.releaseNotes),
    inCategory(SettingsCategory.about, t.settings.rateApp),
    inCategory(
      SettingsCategory.about,
      t.settings.licenses,
      keywords: k.licenses,
    ),
    inCategory(SettingsCategory.about, t.settings.privacyPolicy),
    inCategory(SettingsCategory.about, t.settings.terms),
    inCategory(SettingsCategory.about, t.settings.starOnGitHub),
    inCategory(SettingsCategory.about, t.settings.issueTracker),
    inCategory(SettingsCategory.about, t.settings.contribute),
    inCategory(SettingsCategory.about, t.settings.sourceLicense),
  ];
}

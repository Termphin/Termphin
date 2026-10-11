import '../backup/export_service.dart';
import '../completion/command_completion.dart';
import '../ssh/ssh_session_manager.dart';
import 'action_dock_settings.dart';
import 'anonymize_setting.dart';
import 'desktop_settings.dart';
import 'editor_settings.dart';
import 'floating_dock_settings.dart';
import 'lock_settings.dart';
import 'setting.dart';
import 'sftp_settings.dart';
import 'sidebar_settings.dart';
import 'tab_bar_settings.dart';
import 'terminal_settings.dart';
import 'theme_settings.dart';
import 'toolbar_layout.dart';
import 'upload_settings.dart';

/// Reads every stored preference into memory, once, before the first frame.
///
/// Doing it up front is what lets the rest of the app treat a [Setting] as a
/// plain value: a screen reads `.value` instead of awaiting a load, and there
/// is no window where the terminal is painted in the default scheme and then
/// repainted a frame later in the real one. It is also the only list of what
/// the app persists, which is the point - a setting added without being put
/// here reads as its default forever, and that shows up immediately.
Future<void> loadAppSettings() async {
  await pinLegacyUploadDestination();
  await Future.wait([
    terminalSettings.load(),
    editorSettings.load(),
    floatingDockSettings.load(),
    actionDockSettings.load(),
    toolbarSettings.load(),
    themeModeSetting.load(),
    uploadDestinationSetting.load(),
    uploadAutoPasteSetting.load(),
    anonymizeSetting.load(),
    remoteAgentSetting.load(),
    lastBackupAtSetting.load(),
    sidebarCollapsedSetting.load(),
    sidebarWidthSetting.load(),
    commandSuggestionsSetting.load(),
    sftpShowHiddenSetting.load(),
    sftpFollowTerminalSetting.load(),
    sftpSortFieldSetting.load(),
    sftpSortDescendingSetting.load(),
    tabBarPositionSetting.load(),
    lockTimeoutSetting.load(),
    closeToTraySetting.load(),
  ]);
}

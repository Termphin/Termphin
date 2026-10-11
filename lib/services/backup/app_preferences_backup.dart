import '../completion/command_completion.dart';
import '../settings/action_dock_settings.dart';
import '../settings/desktop_settings.dart';
import '../settings/editor_settings.dart';
import '../settings/floating_dock_settings.dart';
import '../settings/lock_settings.dart';
import '../settings/setting.dart';
import '../settings/sftp_settings.dart';
import '../settings/sidebar_settings.dart';
import '../settings/tab_bar_settings.dart';
import '../settings/terminal_settings.dart';
import '../settings/theme_settings.dart';
import '../settings/toolbar_layout.dart';
import '../settings/upload_settings.dart';
import '../ssh/ssh_session_manager.dart';
import 'form_factor_settings.dart';

/// The `terminalSettings` section of a backup, and its restorer.
///
/// A new setting goes into the backup: add it here, to [exportTerminalSettings]
/// or [exportAppPreferences] and to the matching importer, plus an
/// alternative value in `test/services/settings/app_settings_test.dart`,
/// whose round-trip test fails otherwise.
///
/// Re-read rather than trusting whatever is in memory, since an export can be
/// taken in a process that never loaded them. How text is set belongs to one
/// [FormFactor]: the flat fields carry the phone's, [kDesktopTerminalKey] the
/// desktop's, and the side this device is not comes from the last backup
/// restored here ([OtherFormFactorStore]).
Future<Map<String, dynamic>> exportTerminalSettings({
  required FormFactor formFactor,
}) async {
  final settings = terminalSettings;
  await settings.load();
  final isDesktop = formFactor == FormFactor.desktop;
  final own = {
    'fontFamily': settings.fontFamily.value,
    'fontSize': settings.fontSize.value,
    'lineHeight': settings.lineHeight.value,
    'sidePadding': settings.sidePadding.value,
  };
  final other = await const OtherFormFactorStore().read(
    OtherFormFactorStore.terminal,
  );
  final desktop = isDesktop ? own : other;
  return {
    'schemeId': settings.scheme.value,
    'cursorStyle': settings.cursorStyle.value,
    'cursorBlink': settings.cursorBlink.value,
    'predictiveEcho': settings.predictiveEcho.value,
    ...?(isDesktop ? other : own),
    kDesktopTerminalKey: ?desktop,
  };
}

/// The `appPreferences` section of a backup.
///
/// The active toolbar layout is written out alongside the full profile list,
/// so a backup taken here still restores onto a build that predates
/// profiles. The editor's text settings are split by [FormFactor] like the
/// terminal's, under [kDesktopEditorKey].
Future<Map<String, dynamic>> exportAppPreferences({
  required FormFactor formFactor,
}) async {
  final isDesktop = formFactor == FormFactor.desktop;
  final ownEditor = {
    'editorFontSize': await editorSettings.fontSize.load(),
    'editorFontFamily': await editorSettings.fontFamily.load(),
    'editorLineHeight': await editorSettings.lineHeight.load(),
  };
  final otherEditor = await const OtherFormFactorStore().read(
    OtherFormFactorStore.editor,
  );
  final toolbar = (await toolbarSettings.layout.load());
  final profiles = (await toolbarSettings.profiles.load());
  return {
    'toolbarOrder': toolbar.order,
    'toolbarCustomKeys': (await toolbarSettings.customKeys.load()),
    'toolbarColumns': toolbar.columns,
    'toolbarRows': toolbar.rows,
    'toolbarPages': toolbar.pages,
    'toolbarButtonHeight': toolbar.buttonHeight,
    'toolbarProfiles': [
      for (final profile in profiles.profiles) profile.toJson(),
    ],
    'toolbarActiveProfile': profiles.activeId,
    'toolbarEnabled': await toolbarSettings.enabled.load(),
    'dockOrder': [
      for (final action in await actionDockSettings.order.load()) action.name,
    ],
    'dockHidden': [
      for (final action in await actionDockSettings.hidden.load()) action.name,
    ],
    'dockEnabled': await floatingDockSettings.enabled.load(),
    'themeMode': (await themeModeSetting.load()).name,
    'uploadDestination': (await uploadDestinationSetting.load()).name,
    'uploadAutoPaste': await uploadAutoPasteSetting.load(),
    'remoteAgentEnabled': await remoteAgentSetting.load(),
    'sidebarCollapsed': await sidebarCollapsedSetting.load(),
    'sftpShowHidden': await sftpShowHiddenSetting.load(),
    'sftpFollowTerminal': await sftpFollowTerminalSetting.load(),
    'sftpSortField': (await sftpSortFieldSetting.load()).name,
    'sftpSortDescending': await sftpSortDescendingSetting.load(),
    'commandSuggestions': await commandSuggestionsSetting.load(),
    'tabBarPosition': (await tabBarPositionSetting.load()).name,
    'lockTimeout': (await lockTimeoutSetting.load()).name,
    'closeToTray': await closeToTraySetting.load(),
    'editorWordWrap': await editorSettings.wordWrap.load(),
    'editorLineNumbers': await editorSettings.lineNumbers.load(),
    'editorTabWidth': await editorSettings.tabWidth.load(),
    ...?(isDesktop ? otherEditor : ownEditor),
    kDesktopEditorKey: ?(isDesktop ? ownEditor : otherEditor),
  };
}

/// Restores terminal settings from [ts].
///
/// A field the export did not carry keeps whatever this device has, rather
/// than being reset to the default by its absence. Whatever came in has to
/// go back through the readers' clamping and allow-lists before anything
/// paints with it, hence the final reload. Only this [formFactor]'s text
/// settings are applied; the other side's are kept in [OtherFormFactorStore]
/// so the next backup taken here carries them on.
Future<void> importTerminalSettings(
  Map<String, dynamic> ts, {
  required FormFactor formFactor,
}) async {
  final settings = terminalSettings;
  final isDesktop = formFactor == FormFactor.desktop;

  Future<void> restore<T>(Setting<T> setting, Object? raw) async {
    if (raw is T) await setting.set(raw);
  }

  await restore<String>(settings.scheme, ts['schemeId']);

  final mobile = pickFields(ts, kTerminalFormFactorFields);
  final rawDesktop = ts[kDesktopTerminalKey];
  final desktop = rawDesktop is Map
      ? Map<String, dynamic>.from(rawDesktop)
      : null;
  final own = isDesktop ? desktop : mobile;
  final other = isDesktop ? mobile : desktop;
  if (other != null && other.isNotEmpty) {
    await const OtherFormFactorStore().write(
      OtherFormFactorStore.terminal,
      other,
    );
  }
  final text = own ?? const <String, dynamic>{};
  await restore<String>(settings.fontFamily, text['fontFamily']);
  await restore<double>(
    settings.fontSize,
    (text['fontSize'] as num?)?.toDouble(),
  );
  await restore<double>(
    settings.lineHeight,
    (text['lineHeight'] as num?)?.toDouble(),
  );
  await restore<double>(
    settings.sidePadding,
    (text['sidePadding'] as num?)?.toDouble(),
  );
  await restore<String>(settings.cursorStyle, ts['cursorStyle']);
  await restore<bool>(settings.cursorBlink, ts['cursorBlink']);
  await restore<bool>(settings.predictiveEcho, ts['predictiveEcho']);
  await settings.load();
}

/// Restores app preferences from [appPrefs].
///
/// The single-layout `toolbarOrder` is applied first, and then, when
/// present, the full `toolbarProfiles` list - a file holding both is one
/// written by a build that has profiles, and its active profile is the
/// layout to end on; a shared id there is the same layout under two names,
/// so the incoming one replaces it rather than landing beside it. A dock
/// action this build has but the backup predates lands at the end of
/// `dockOrder` rather than disappearing from the dock. The editor's text
/// settings follow [formFactor] as in [importTerminalSettings].
Future<void> importAppPreferences(
  Map<String, dynamic> appPrefs, {
  required FormFactor formFactor,
}) async {
  final isDesktop = formFactor == FormFactor.desktop;
  final toolbarOrderRaw = appPrefs['toolbarOrder'] as List?;
  if (toolbarOrderRaw != null) {
    final current = (await toolbarSettings.layout.load());
    final imported = current.copyWith(
      order: toolbarOrderRaw.map((e) => e?.toString() ?? '').toList(),
      columns: (appPrefs['toolbarColumns'] as num?)?.toInt(),
      rows: (appPrefs['toolbarRows'] as num?)?.toInt(),
      pages: (appPrefs['toolbarPages'] as num?)?.toInt(),
      buttonHeight: (appPrefs['toolbarButtonHeight'] as num?)?.toDouble(),
    );
    await saveToolbarLayout(imported);
  }

  final profilesRaw = appPrefs['toolbarProfiles'] as List?;
  if (profilesRaw != null) {
    final imported = [
      for (final entry in profilesRaw)
        if (entry is Map<String, dynamic>) ToolbarProfile.fromJson(entry),
    ].nonNulls.toList();
    if (imported.isNotEmpty) {
      final importedIds = imported.map((p) => p.id).toSet();
      final current = await toolbarSettings.profiles.load();
      final merged = ToolbarProfiles(
        profiles: [
          for (final profile in current.profiles)
            if (!importedIds.contains(profile.id)) profile,
          ...imported,
        ],
        activeId: appPrefs['toolbarActiveProfile'] as String?,
      );
      await saveToolbarProfiles(merged);
      await activateToolbarProfile(merged.activeId);
    }
  }

  final customKeysRaw = appPrefs['toolbarCustomKeys'] as List?;
  if (customKeysRaw != null) {
    await saveToolbarCustomKeys(
      customKeysRaw.map((e) => e?.toString() ?? '').toList(),
    );
  }

  final dockOrderRaw = appPrefs['dockOrder'] as List?;
  if (dockOrderRaw != null) {
    final ordered = _dockActions(dockOrderRaw);
    for (final action in DockAction.values) {
      if (!ordered.contains(action)) ordered.add(action);
    }
    await actionDockSettings.order.set(ordered);
  }

  final dockHiddenRaw = appPrefs['dockHidden'] as List?;
  if (dockHiddenRaw != null) {
    await actionDockSettings.hidden.set(_dockActions(dockHiddenRaw).toSet());
  }

  final toolbarEnabled = appPrefs['toolbarEnabled'];
  if (toolbarEnabled is bool) {
    await toolbarSettings.enabled.set(toolbarEnabled);
  }

  final dockEnabled = appPrefs['dockEnabled'];
  if (dockEnabled is bool) {
    await floatingDockSettings.enabled.set(dockEnabled);
  }

  final themeMode = _byName(AppThemeMode.values, appPrefs['themeMode']);
  if (themeMode != null) await themeModeSetting.set(themeMode);

  final lockTimeout = _byName(LockTimeout.values, appPrefs['lockTimeout']);
  if (lockTimeout != null) await lockTimeoutSetting.set(lockTimeout);

  final uploadDestination = _byName(
    UploadDestination.values,
    appPrefs['uploadDestination'],
  );
  if (uploadDestination != null) {
    await uploadDestinationSetting.set(uploadDestination);
  }

  final uploadAutoPaste = appPrefs['uploadAutoPaste'];
  if (uploadAutoPaste is bool) {
    await uploadAutoPasteSetting.set(uploadAutoPaste);
  }

  final remoteAgent = appPrefs['remoteAgentEnabled'];
  if (remoteAgent is bool) await remoteAgentSetting.set(remoteAgent);

  final sidebarCollapsed = appPrefs['sidebarCollapsed'];
  if (sidebarCollapsed is bool) {
    await sidebarCollapsedSetting.set(sidebarCollapsed);
  }

  final sftpShowHidden = appPrefs['sftpShowHidden'];
  if (sftpShowHidden is bool) await sftpShowHiddenSetting.set(sftpShowHidden);

  final sftpFollowTerminal = appPrefs['sftpFollowTerminal'];
  if (sftpFollowTerminal is bool) {
    await sftpFollowTerminalSetting.set(sftpFollowTerminal);
  }

  final sftpSortField = _byName(
    SftpSortField.values,
    appPrefs['sftpSortField'],
  );
  if (sftpSortField != null) await sftpSortFieldSetting.set(sftpSortField);

  final sftpSortDescending = appPrefs['sftpSortDescending'];
  if (sftpSortDescending is bool) {
    await sftpSortDescendingSetting.set(sftpSortDescending);
  }

  final commandSuggestions = appPrefs['commandSuggestions'];
  if (commandSuggestions is bool) {
    await commandSuggestionsSetting.set(commandSuggestions);
  }

  final tabBarPosition = _byName(
    TabBarPosition.values,
    appPrefs['tabBarPosition'],
  );
  if (tabBarPosition != null) await tabBarPositionSetting.set(tabBarPosition);

  final closeToTray = appPrefs['closeToTray'];
  if (closeToTray is bool) await closeToTraySetting.set(closeToTray);

  final editorWordWrap = appPrefs['editorWordWrap'];
  if (editorWordWrap is bool) {
    await editorSettings.wordWrap.set(editorWordWrap);
  }
  final mobileEditor = pickFields(appPrefs, kEditorFormFactorFields);
  final rawDesktopEditor = appPrefs[kDesktopEditorKey];
  final desktopEditor = rawDesktopEditor is Map
      ? Map<String, dynamic>.from(rawDesktopEditor)
      : null;
  final otherEditor = isDesktop ? mobileEditor : desktopEditor;
  if (otherEditor != null && otherEditor.isNotEmpty) {
    await const OtherFormFactorStore().write(
      OtherFormFactorStore.editor,
      otherEditor,
    );
  }
  final editorText =
      (isDesktop ? desktopEditor : mobileEditor) ?? const <String, dynamic>{};
  final editorFontSize = editorText['editorFontSize'];
  if (editorFontSize is num) {
    await editorSettings.fontSize.set(editorFontSize.toDouble());
  }
  final editorFontFamily = editorText['editorFontFamily'];
  if (editorFontFamily is String &&
      kTerminalFontLabels.containsKey(editorFontFamily)) {
    await editorSettings.fontFamily.set(editorFontFamily);
  }
  final editorLineHeight = editorText['editorLineHeight'];
  if (editorLineHeight is num) {
    await editorSettings.lineHeight.set(editorLineHeight.toDouble());
  }
  final editorTabWidth = appPrefs['editorTabWidth'];
  if (editorTabWidth is int) {
    await editorSettings.tabWidth.set(editorTabWidth);
  }
  final editorLineNumbers = appPrefs['editorLineNumbers'];
  if (editorLineNumbers is bool) {
    await editorSettings.lineNumbers.set(editorLineNumbers);
  }
}

List<DockAction> _dockActions(List<dynamic> raw) => [
  for (final entry in raw) ?_byName(DockAction.values, entry),
];

T? _byName<T extends Enum>(List<T> values, Object? name) =>
    values.where((value) => value.name == name).firstOrNull;

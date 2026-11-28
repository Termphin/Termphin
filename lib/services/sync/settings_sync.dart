import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backup/app_preferences_backup.dart';
import '../completion/command_completion.dart';
import '../settings/action_dock_settings.dart';
import '../settings/desktop_settings.dart';
import '../settings/editor_settings.dart';
import '../settings/floating_dock_settings.dart';
import '../settings/sftp_settings.dart';
import '../settings/terminal_settings.dart';
import '../settings/theme_settings.dart';
import '../settings/toolbar_layout.dart';
import '../settings/upload_settings.dart';
import '../ssh/ssh_session_manager.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';

/// Preferences that follow the account to every device, grouped into the
/// records they sync as. Keys are the backup's own (`terminal.<key>` for
/// its terminal section, `app.<key>` for app preferences); the keys in one
/// group only mean something together - a font with its line height, the
/// toolbar profiles with the one that is active - so they travel as one.
@visibleForTesting
const kSyncedSettingGroups = <String, List<String>>{
  'terminal.scheme': ['terminal.schemeId'],
  'terminal.font': ['terminal.fontFamily', 'terminal.lineHeight'],
  'terminal.cursor': ['terminal.cursorStyle', 'terminal.cursorBlink'],
  'terminal.predictiveEcho': ['terminal.predictiveEcho'],
  'terminal.programNotifications': ['terminal.programNotifications'],
  'terminal.notices': [
    'terminal.finishedNotifications',
    'terminal.quietNotifications',
    'terminal.noticeLines',
  ],
  'terminal.openAppNotices': [
    'terminal.openAppNotices',
    'terminal.openAppNoticeStyle',
  ],
  'terminal.mouseKeyboardGuard': ['terminal.mouseKeyboardGuard'],
  'app.toolbarProfiles': ['app.toolbarProfiles', 'app.toolbarActiveProfile'],
  'app.toolbarCustomKeys': ['app.toolbarCustomKeys'],
  'app.toolbarEnabled': ['app.toolbarEnabled'],
  'app.dock': ['app.dockOrder', 'app.dockHidden', 'app.dockEnabled'],
  'app.themeMode': ['app.themeMode'],
  'app.upload': ['app.uploadDestination', 'app.uploadAutoPaste'],
  'app.remoteAgentEnabled': ['app.remoteAgentEnabled'],
  'app.sftp': [
    'app.sftpShowHidden',
    'app.sftpFollowTerminal',
    'app.sftpSortField',
    'app.sftpSortDescending',
  ],
  'app.commandSuggestions': ['app.commandSuggestions'],
  'app.profileFormMoreOptions': ['app.profileFormMoreOptions'],
  'app.closeToTray': ['app.closeToTray'],
  'app.editor': [
    'app.editorWordWrap',
    'app.editorFontFamily',
    'app.editorLineNumbers',
    'app.editorLineHeight',
    'app.editorTabWidth',
  ],
};

/// Preferences that stay with the device: sizes that depend on its screen,
/// the scrollback its memory carries, the lock, and where its panes sit. Everything the backup carries is in
/// exactly one of the two lists, which a test holds it to.
@visibleForTesting
const kDeviceSettings = <String>{
  'terminal.fontSize',
  'terminal.sidePadding',
  'terminal.scrollbackLines',
  'app.toolbarOrder',
  'app.toolbarColumns',
  'app.toolbarRows',
  'app.toolbarPages',
  'app.toolbarButtonHeight',
  'app.sidebarCollapsed',
  'app.tabBarPosition',
  'app.lockTimeout',
  'app.editorFontSize',
  'app.showThisComputer',
};

/// The kind settings records sync under.
const kSettingKind = 'setting';

const _timesPrefsKey = 'sync_setting_times';

Map<String, Object?> _groupData(
  Map<String, Object?> values,
  List<String> keys,
) => {
  for (final key in keys)
    if (values.containsKey(key)) key: values[key],
};

/// The synced preferences as [SyncRecord]s, and back.
///
/// A preference has no time of its own, so this remembers, per record, a
/// hash of its value and when that hash last changed on this device - what
/// settles a conflict when two devices changed the same group.
class SettingsSync {
  /// Forgets the time kept per group, when this device leaves sync.
  static Future<void> forgetTimes() async {
    await (await SharedPreferences.getInstance()).remove(_timesPrefsKey);
  }

  /// The settings whose change should prompt a sync, for the coordinator to
  /// listen to.
  static List<Listenable> get listenables => [
    terminalSettings.scheme,
    terminalSettings.fontFamily,
    terminalSettings.lineHeight,
    terminalSettings.cursorStyle,
    terminalSettings.cursorBlink,
    terminalSettings.predictiveEcho,
    terminalSettings.programNotifications,
    terminalSettings.finishedNotifications,
    terminalSettings.quietNotifications,
    terminalSettings.noticeLines,
    terminalSettings.openAppNotices,
    terminalSettings.openAppNoticeStyle,
    terminalSettings.mouseKeyboardGuard,
    toolbarSettings.profiles,
    toolbarSettings.customKeys,
    toolbarSettings.enabled,
    actionDockSettings.order,
    actionDockSettings.hidden,
    floatingDockSettings.enabled,
    themeModeSetting,
    uploadDestinationSetting,
    uploadAutoPasteSetting,
    remoteAgentSetting,
    sftpShowHiddenSetting,
    sftpFollowTerminalSetting,
    sftpSortFieldSetting,
    sftpSortDescendingSetting,
    commandSuggestionsSetting,
    closeToTraySetting,
    editorSettings.wordWrap,
    editorSettings.fontFamily,
    editorSettings.lineNumbers,
    editorSettings.lineHeight,
    editorSettings.tabWidth,
  ];

  /// The groups as they stand here. A group's time is the moment its hash
  /// was first seen to change on this device; a group first seen by sync is
  /// stamped epoch 0, so edits made before sync was turned on carry no time.
  Future<List<SyncRecord>> readAll() async {
    final values = await _exported();
    final times = await _times();
    final now = clock.now().toUtc();
    var changed = false;
    final records = <SyncRecord>[];
    for (final MapEntry(key: id, value: keys) in kSyncedSettingGroups.entries) {
      final data = _groupData(values, keys);
      final hash = contentHash(data);
      final known = times[id];
      DateTime at;
      if (known != null && known.$1 == hash) {
        at = known.$2;
      } else {
        at = known == null
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : now;
        times[id] = (hash, at);
        changed = true;
      }
      records.add(
        SyncRecord(kind: kSettingKind, id: id, data: data, updatedAt: at),
      );
    }
    if (changed) await _saveTimes(times);
    return records;
  }

  /// Applies another device's [record], through the backup's importers so
  /// it passes the same checks a restored backup does.
  Future<void> upsert(SyncRecord record) async {
    if (!kSyncedSettingGroups.containsKey(record.id)) return;
    final terminal = <String, dynamic>{};
    final app = <String, dynamic>{};
    for (final MapEntry(:key, :value) in record.data.entries) {
      if (key.startsWith('terminal.')) {
        terminal[key.substring('terminal.'.length)] = value;
      } else if (key.startsWith('app.')) {
        app[key.substring('app.'.length)] = value;
      }
    }
    if (terminal.isNotEmpty) await importTerminalSettings(terminal);
    if (app.isNotEmpty) await importAppPreferences(app);
    final applied = await _exported();
    final data = _groupData(applied, kSyncedSettingGroups[record.id]!);
    final times = await _times();
    times[record.id] = (contentHash(data), record.updatedAt);
    await _saveTimes(times);
  }

  Future<Map<String, Object?>> _exported() async => {
    for (final MapEntry(:key, :value)
        in (await exportTerminalSettings()).entries)
      'terminal.$key': value,
    for (final MapEntry(:key, :value) in (await exportAppPreferences()).entries)
      'app.$key': value,
  };

  Future<Map<String, (String, DateTime)>> _times() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _timesPrefsKey,
    );
    if (raw == null) return {};
    try {
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          key: (
            (value as List)[0] as String,
            DateTime.fromMillisecondsSinceEpoch(value[1] as int, isUtc: true),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveTimes(Map<String, (String, DateTime)> times) async {
    await (await SharedPreferences.getInstance()).setString(
      _timesPrefsKey,
      jsonEncode({
        for (final MapEntry(:key, :value) in times.entries)
          key: [value.$1, value.$2.millisecondsSinceEpoch],
      }),
    );
  }
}

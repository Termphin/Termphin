import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/backup/export_service.dart';
import 'package:termphin/services/completion/command_completion.dart';
import 'package:termphin/services/settings/action_dock_settings.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/desktop_settings.dart';
import 'package:termphin/services/settings/editor_settings.dart';
import 'package:termphin/services/settings/floating_dock_settings.dart';
import 'package:termphin/services/settings/lock_settings.dart';
import 'package:termphin/services/settings/setting.dart';
import 'package:termphin/services/settings/sftp_settings.dart';
import 'package:termphin/services/settings/sidebar_settings.dart';
import 'package:termphin/services/settings/tab_bar_settings.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/settings/theme_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/services/settings/upload_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

/// Every [Setting] `loadAppSettings()` actually reaches, flattened.
List<Setting<Object?>> get _loaded => [
  ...terminalSettings.all,
  ...editorSettings.all,
  ...floatingDockSettings.all,
  ...actionDockSettings.all,
  toolbarSettings.layout,
  toolbarSettings.profiles,
  toolbarSettings.customKeys,
  toolbarSettings.enabled,
  themeModeSetting,
  uploadDestinationSetting,
  uploadAutoPasteSetting,
  anonymizeSetting,
  remoteAgentSetting,
  lastBackupAtSetting,
  sidebarCollapsedSetting,
  commandSuggestionsSetting,
  sftpShowHiddenSetting,
  sftpFollowTerminalSetting,
  sftpSortFieldSetting,
  sftpSortDescendingSetting,
  tabBarPositionSetting,
  lockTimeoutSetting,
  closeToTraySetting,
];

/// Where a `Setting` is built, found by reading the source rather than by
/// asking the objects - the point is to catch one that exists and is not
/// wired into [loadAppSettings], which no runtime walk of the wired ones can
/// see by definition.
final _declaration = RegExp(
  r'^\s*(?:final|static final)\s+(?:Setting<[^=]*?>\s+)?(\w+)\s*=\s*Setting\s*[.<]',
  multiLine: true,
);

List<String> _declaredSettings() {
  final found = <String>[];
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    for (final match in _declaration.allMatches(file.readAsStringSync())) {
      found.add('${file.path}:${match.group(1)}');
    }
  }
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadAppSettings', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await loadAppSettings();
    });

    test('reaches every Setting declared in lib/', () {
      expect(
        _declaredSettings(),
        hasLength(_loaded.length),
        reason:
            'lib/ declares ${_declaredSettings().length} settings but '
            'loadAppSettings() reaches ${_loaded.length}. Wire the new one '
            'into its group (or into loadAppSettings directly).\n'
            'Declared:\n  ${_declaredSettings().join('\n  ')}',
      );
    });

    test('no two settings share a preferences key', () {
      final keys = [for (final setting in _loaded) setting.key];
      expect(keys.toSet(), hasLength(keys.length), reason: 'keys: $keys');
    });

    test('leaves every setting at its fallback when nothing is stored', () {
      for (final setting in _loaded) {
        expect(setting.value, setting.fallback, reason: setting.key);
      }
    });

    test('covers every reached setting with an alternative value', () {
      expect(_alternatives.keys.toSet(), _loaded.toSet());
    });

    test('applies what is stored, for every setting it reaches', () async {
      for (final entry in _alternatives.entries) {
        await entry.key.set(entry.value);
        entry.key.value = entry.key.fallback;
      }

      await loadAppSettings();

      for (final entry in _alternatives.entries) {
        expect(
          entry.key.value,
          entry.value,
          reason: '${entry.key.key} was not read back by loadAppSettings()',
        );
      }
    });

    test('a backup carries every setting not left out on purpose', () async {
      final service = ExportService();
      const settingsOnly = ExportOptions(
        includeProfiles: false,
        includeSshKeys: false,
        includeSnippets: false,
      );
      for (final entry in _alternatives.entries) {
        await entry.key.set(entry.value);
      }
      final exported = await service.exportToJson(settingsOnly);

      SharedPreferences.setMockInitialValues({});
      await loadAppSettings();
      await service.importFromJson(exported, const ImportOptions());
      await loadAppSettings();

      for (final entry in _alternatives.entries) {
        if (_notBackedUp.contains(entry.key)) continue;
        final expected = entry.key == toolbarSettings.layout
            ? (_alternatives[toolbarSettings.profiles]! as ToolbarProfiles)
                  .active
                  .layout
            : entry.value;
        expect(
          entry.key.value,
          expected,
          reason:
              '${entry.key.key} does not survive a backup. Add it to '
              'ExportService, or to _notBackedUp if it is device state.',
        );
      }
    });

    test('is what makes a value readable without awaiting a load', () async {
      await terminalSettings.fontSize.set(18);
      SharedPreferences.setMockInitialValues({
        terminalSettings.fontSize.key: 21.0,
      });
      await loadAppSettings();
      expect(terminalSettings.fontSize.value, 21);
    });
  });
}

/// Settings a backup leaves behind: a gesture's leftovers, a demo switch and
/// the backup's own bookkeeping.
final Set<Setting<Object?>> _notBackedUp = {
  floatingDockSettings.side,
  floatingDockSettings.verticalFraction,
  anonymizeSetting,
  lastBackupAtSetting,
};

/// A legal value for each setting that is not its fallback, written out with
/// its real type - a collection reached through `Setting<Object?>` loses its
/// element type, and `set` would reject the rebuilt value.
///
/// `actionDockSettings.hidden` is empty here because empty is the deliberate
/// "show everything", which is exactly the value a plain default would lose.
/// `toolbarSettings.profiles` carries two layouts with the second in use, so
/// the active id is half of this value and a reader that dropped it would
/// still look right with one profile.
final Map<Setting<Object?>, Object?> _alternatives = {
  terminalSettings.scheme: kTerminalSchemeLabels.keys.firstWhere(
    (name) => name != terminalSettings.scheme.fallback,
  ),
  terminalSettings.lineHeight: 1.4,
  terminalSettings.sidePadding: 11.0,
  terminalSettings.fontSize: kTerminalDefaultFontSize + 2,
  terminalSettings.cursorStyle: kCursorStyles.firstWhere(
    (style) => style != terminalSettings.cursorStyle.fallback,
  ),
  terminalSettings.cursorBlink: false,
  terminalSettings.predictiveEcho: false,
  terminalSettings.fontFamily: kTerminalFontLabels.keys.firstWhere(
    (name) => name != terminalSettings.fontFamily.fallback,
  ),
  editorSettings.fontSize: 16.5,
  editorSettings.fontFamily: kTerminalFontLabels.keys.firstWhere(
    (name) => name != editorSettings.fontFamily.fallback,
  ),
  sftpShowHiddenSetting: true,
  sftpFollowTerminalSetting: false,
  sftpSortFieldSetting: SftpSortField.modified,
  sftpSortDescendingSetting: true,
  editorSettings.lineHeight: 1.8,
  editorSettings.tabWidth: 4,
  editorSettings.lineNumbers: false,
  editorSettings.wordWrap: false,
  floatingDockSettings.side: FloatingDockSide.left,
  floatingDockSettings.verticalFraction: 0.25,
  floatingDockSettings.enabled: false,
  actionDockSettings.order: DockAction.values.reversed.toList(),
  actionDockSettings.hidden: <DockAction>{},
  toolbarSettings.layout: ToolbarLayout.defaults.copyWith(
    buttonHeight: ToolbarLayout.defaults.buttonHeight + 3,
  ),
  toolbarSettings.customKeys: <String>[
    kDefaultToolbarOrder.firstWhere(isValidToolbarActionId),
  ],
  toolbarSettings.profiles: ToolbarProfiles(
    profiles: [
      ToolbarProfile(
        id: kDefaultToolbarProfileId,
        name: '',
        layout: ToolbarLayout.defaults,
      ),
      ToolbarProfile(id: 'second', name: 'Second', layout: ToolbarLayout.blank),
    ],
    activeId: 'second',
  ),
  toolbarSettings.enabled: false,
  themeModeSetting: AppThemeMode.values.firstWhere(
    (mode) => mode != themeModeSetting.fallback,
  ),
  uploadDestinationSetting: UploadDestination.values.firstWhere(
    (destination) => destination != uploadDestinationSetting.fallback,
  ),
  uploadAutoPasteSetting: !uploadAutoPasteSetting.fallback,
  anonymizeSetting: !anonymizeSetting.fallback,
  remoteAgentSetting: !remoteAgentSetting.fallback,
  lastBackupAtSetting: '2026-05-06T07:08:09.000Z',
  sidebarCollapsedSetting: !sidebarCollapsedSetting.fallback,
  commandSuggestionsSetting: !commandSuggestionsSetting.fallback,
  tabBarPositionSetting: TabBarPosition.bottom,
  lockTimeoutSetting: LockTimeout.minutes5,
  closeToTraySetting: !closeToTraySetting.fallback,
};

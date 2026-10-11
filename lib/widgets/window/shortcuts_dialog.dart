import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/app_commands.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../sftp/sftp_shortcuts.dart';
import '../ui/app_sheet.dart';
import '../ui/section_header.dart';

/// Every keyboard shortcut, read off the same table the keyboard handler
/// uses, so this list cannot drift from what the keys actually do.
Future<void> showShortcutsDialog(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => const _ShortcutsList(),
  );
}

class _ShortcutsList extends StatelessWidget {
  const _ShortcutsList();

  static const _general = [
    AppCommand.globalSearch,
    AppCommand.newMachine,
    AppCommand.openSettings,
    AppCommand.toggleSidebar,
    AppCommand.openManual,
    AppCommand.showShortcuts,
    AppCommand.quit,
  ];

  static const _terminal = [
    AppCommand.newSession,
    AppCommand.closeTab,
    AppCommand.nextTab,
    AppCommand.previousTab,
    AppCommand.selectTab,
    AppCommand.findInTerminal,
    AppCommand.toggleFiles,
    AppCommand.endSession,
    AppCommand.uploadFile,
    AppCommand.zoomIn,
    AppCommand.zoomOut,
    AppCommand.zoomReset,
  ];

  /// Lists the terminal's own clipboard keys too, which it handles itself.
  /// Off a Mac Ctrl+C copies only with something selected; without, it is
  /// the shell's interrupt as ever.
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final mac = isMacOSPlatform;
    String terminalKey(LogicalKeyboardKey key) => AppCommands.describeActivator(
      mac
          ? SingleActivator(key, meta: true)
          : SingleActivator(
              key,
              control: true,
              shift: key == LogicalKeyboardKey.keyA,
            ),
    );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        Text(
          t.commands.shortcutsTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        SectionHeader(t.commands.shortcutsGeneral),
        const SizedBox(height: 6),
        for (final command in _general)
          _Row(
            label: AppCommands.label(t, command),
            keys: AppCommands.shortcutLabel(command) ?? '',
          ),
        const SizedBox(height: 16),
        SectionHeader(t.commands.shortcutsTerminal),
        const SizedBox(height: 6),
        for (final command in _terminal)
          _Row(
            label: AppCommands.label(t, command),
            keys: AppCommands.shortcutLabel(command) ?? '',
          ),
        _Row(
          label: t.commands.shortcutsCopy,
          keys: terminalKey(LogicalKeyboardKey.keyC),
        ),
        _Row(
          label: t.commands.shortcutsPaste,
          keys: terminalKey(LogicalKeyboardKey.keyV),
        ),
        _Row(
          label: t.commands.shortcutsSelectAll,
          keys: terminalKey(LogicalKeyboardKey.keyA),
        ),
        const SizedBox(height: 16),
        SectionHeader(t.commands.shortcutsFiles),
        const SizedBox(height: 6),
        for (final (label, activator) in [
          (t.sftp.openItem, SftpShortcuts.open),
          (t.sftp.parentFolder, SftpShortcuts.parentFolder),
          (t.sftp.back, SftpShortcuts.back),
          (t.sftp.newFolder, SftpShortcuts.newFolder),
          (t.sftp.newFile, SftpShortcuts.newFile),
          (t.common.rename, SftpShortcuts.rename),
          (t.sftp.download, SftpShortcuts.download),
          (t.sftp.copyTo, SftpShortcuts.copyTo),
          (t.sftp.moveTo, SftpShortcuts.moveTo),
          (t.common.delete, SftpShortcuts.delete),
          (t.sftp.selectAll, SftpShortcuts.selectAll),
          (t.common.refresh, SftpShortcuts.refresh),
          (t.sftp.showHidden, SftpShortcuts.toggleHidden),
        ])
          _Row(label: label, keys: AppCommands.describeActivator(activator)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: colors.uiStyle.copyWith(color: colors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.fieldFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Text(
              keys,
              style: colors.uiSmall.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../ui/app_dropdown.dart';

enum _SelectionAction { selectAll, download }

/// Replaces [SftpPathBar] once at least one row is selected: a count, and the
/// actions that work on the whole selection.
class SftpSelectionBar extends StatelessWidget {
  const SftpSelectionBar({
    super.key,
    required this.count,
    required this.copyAvailable,
    required this.onClear,
    required this.onCopy,
    required this.onMove,
    required this.onDelete,
    required this.onSelectAll,
    required this.onDownload,
  });

  final int count;

  /// A copy runs `cp` on the server; an account locked to SFTP has no way to.
  final bool copyAvailable;
  final VoidCallback onClear;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onSelectAll;
  final VoidCallback onDownload;

  /// Select all and download sit in the overflow menu rather than on the bar
  /// itself, so it still fits a split pane's width.
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    return Container(
      color: colors.surfaceCard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              PhosphorIconsRegular.x,
              color: colors.textPrimary,
              size: 20,
            ),
            onPressed: onClear,
          ),
          Expanded(
            child: Text(
              t.sftp.selectedCount(count: count),
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsFill.folders, size: 20),
            color: colors.textSecondary,
            tooltip: copyAvailable ? t.sftp.copyTo : t.sftp.errors.noShell,
            onPressed: copyAvailable ? onCopy : null,
          ),
          IconButton(
            icon: Icon(
              PhosphorIconsFill.arrowSquareRight,
              color: colors.textSecondary,
              size: 20,
            ),
            tooltip: t.sftp.moveTo,
            onPressed: onMove,
          ),
          IconButton(
            icon: Icon(PhosphorIconsFill.trash, color: colors.error, size: 20),
            tooltip: t.common.delete,
            onPressed: onDelete,
          ),
          AppActionDropdown<_SelectionAction>(
            iconSize: 20,
            iconColor: colors.textSecondary,
            buttonSize: 40,
            width: 220,
            tooltip: t.sftp.moreActions,
            onSelected: (action) {
              switch (action) {
                case _SelectionAction.selectAll:
                  onSelectAll();
                case _SelectionAction.download:
                  onDownload();
              }
            },
            items: [
              DropdownItem(
                value: _SelectionAction.selectAll,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsRegular.checkSquare,
                  label: t.sftp.selectAll,
                ),
              ),
              DropdownItem(
                value: _SelectionAction.download,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsFill.downloadSimple,
                  label: t.sftp.download,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../ui/context_bar.dart';

/// Replaces [SftpPathBar] once at least one row is selected: a count, and the
/// actions that work on the whole selection, on the same [ContextBar] the
/// other lists select with.
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

  /// Select all always sits in the menu; download joins it when the bar is
  /// too narrow, as in a split pane.
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    return ContextBar(
      selection: true,
      leading: ContextBarClose(tooltip: t.selection.clear, onPressed: onClear),
      title: t.sftp.selectedCount(count: count),
      actions: [
        ContextBarAction(
          icon: PhosphorIconsFill.folders,
          label: t.sftp.copyTo,
          tooltip: copyAvailable ? null : t.sftp.errors.noShell,
          onPressed: copyAvailable ? onCopy : null,
        ),
        ContextBarAction(
          icon: PhosphorIconsFill.arrowSquareRight,
          label: t.sftp.moveTo,
          onPressed: onMove,
        ),
        ContextBarAction(
          icon: PhosphorIconsFill.trash,
          label: t.common.delete,
          color: colors.error,
          onPressed: onDelete,
        ),
        ContextBarAction(
          icon: PhosphorIconsFill.downloadSimple,
          label: t.sftp.download,
          onPressed: onDownload,
        ),
      ],
      menu: [
        ContextBarAction(
          icon: PhosphorIconsRegular.checkSquare,
          label: t.sftp.selectAll,
          onPressed: onSelectAll,
        ),
      ],
    );
  }
}

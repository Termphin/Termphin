import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import '../../utils/file_icon.dart';
import '../../utils/format_size.dart';
import '../../utils/text_sniffer.dart';
import 'sftp_file_actions_menu.dart';

String _formatModified(int? epochSeconds) {
  if (epochSeconds == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return DateFormat('MMM d, HH:mm').format(date);
}

/// One row of the directory listing: its icon, name, size and modified time,
/// a selection checkmark once [selectionMode] is on, and the `⋮` actions menu
/// otherwise.
class SftpFileRow extends StatelessWidget {
  const SftpFileRow({
    super.key,
    required this.item,
    required this.path,
    required this.isSelected,
    required this.selectionMode,
    required this.isProbing,
    required this.probe,
    required this.runProbe,
    required this.opener,
    required this.copyAvailable,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final SftpName item;

  /// The item's full remote path, already joined onto the current directory.
  final String path;
  final bool isSelected;
  final bool selectionMode;

  /// Whether [path] is the one [onAction]'s caller is currently sniffing the
  /// contents of, for a spinner in place of the file icon.
  final bool isProbing;
  final TextProbe? probe;
  final Future<TextProbe?> Function() runProbe;
  final ValueNotifier<Object?> opener;
  final bool copyAvailable;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<SftpFileAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = colors.primary;
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    final textTertiary = textPrimary.withValues(alpha: 0.58);
    final isDir = item.attr.isDirectory;
    final isUp = item.filename == '..';

    return Material(
      color: isSelected ? accent.withValues(alpha: 0.12) : accent.invisible,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.surfaceDivider)),
          ),
          child: Row(
            children: [
              if (selectionMode && !isUp)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected
                        ? PhosphorIconsRegular.checkCircle
                        : PhosphorIconsFill.circle,
                    color: isSelected ? accent : textTertiary,
                    size: 20,
                  ),
                ),
              if (isProbing)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  ),
                )
              else if (isUp || isDir)
                Icon(
                  isUp
                      ? PhosphorIconsFill.folderOpen
                      : PhosphorIconsFill.folder,
                  color: accent,
                  size: 24,
                )
              else
                buildFileIcon(
                  item.filename,
                  size: 24,
                  fallbackColor: textSecondary,
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.filename,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isUp &&
                        (item.attr.size != null ||
                            item.attr.modifyTime != null)) ...[
                      const SizedBox(height: 1),
                      Text(
                        [
                          if (!isDir && item.attr.size != null)
                            formatFileSize(item.attr.size),
                          if (item.attr.modifyTime != null)
                            _formatModified(item.attr.modifyTime),
                        ].where((s) => s.isNotEmpty).join('  ·  '),
                        style: TextStyle(color: textTertiary, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isUp && !selectionMode)
                SftpFileActionsMenu(
                  item: item,
                  probe: probe,
                  runProbe: runProbe,
                  opener: opener,
                  copyAvailable: copyAvailable,
                  onAction: onAction,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

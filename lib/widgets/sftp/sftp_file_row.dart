import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/sftp_settings.dart';
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

/// A table's date is a full one: a column is read down, where "Mar 4" under
/// "Nov 12" says nothing about the year either belongs to.
String _formatModifiedColumn(int? epochSeconds) {
  if (epochSeconds == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return DateFormat('yyyy-MM-dd HH:mm').format(date);
}

/// Height of a row in a desktop's listing. Fixed, so the browser knows where
/// a row is without it having been built - which is what lets the keyboard
/// scroll to one that is off screen.
const double kSftpRowHeight = 30;

/// Which columns a desktop's listing has room for beside the name. A narrow
/// pane drops the date first and then the size, rather than leaving the name
/// a few characters.
class SftpColumns {
  const SftpColumns({required this.size, required this.modified});

  factory SftpColumns.forWidth(double width) =>
      SftpColumns(size: width >= 360, modified: width >= 520);

  final bool size;
  final bool modified;
}

const double _kSizeColumnWidth = 88;
const double _kModifiedColumnWidth = 132;
const double _kActionsColumnWidth = 40;
const double _kColumnGap = 16;
const double _kColumnIconSize = 18;
const double _kColumnIconGap = 10;
const double _kRowInset = 16;

/// The header over a desktop's listing: a click on a column sorts by it, a
/// second click on the same one turns the order around.
///
/// It is laid out with the row's own measurements, so each label stands over
/// what it names.
class SftpColumnHeader extends StatelessWidget {
  const SftpColumnHeader({
    super.key,
    required this.columns,
    required this.field,
    required this.descending,
    required this.onSort,
  });

  final SftpColumns columns;
  final SftpSortField field;
  final bool descending;
  final void Function(SftpSortField field, bool descending) onSort;

  void _sortBy(SftpSortField column) =>
      onSort(column, column == field ? !descending : false);

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _kRowInset),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _kColumnIconSize + _kColumnIconGap),
          Expanded(
            child: _ColumnLabel(
              label: t.sftp.sortName,
              sorted: field == SftpSortField.name,
              descending: descending,
              onTap: () => _sortBy(SftpSortField.name),
            ),
          ),
          if (columns.size) ...[
            const SizedBox(width: _kColumnGap),
            SizedBox(
              width: _kSizeColumnWidth,
              child: _ColumnLabel(
                label: t.sftp.sortSize,
                sorted: field == SftpSortField.size,
                descending: descending,
                alignEnd: true,
                onTap: () => _sortBy(SftpSortField.size),
              ),
            ),
          ],
          if (columns.modified) ...[
            const SizedBox(width: _kColumnGap),
            SizedBox(
              width: _kModifiedColumnWidth,
              child: _ColumnLabel(
                label: t.sftp.sortModified,
                sorted: field == SftpSortField.modified,
                descending: descending,
                onTap: () => _sortBy(SftpSortField.modified),
              ),
            ),
          ],
          const SizedBox(width: _kActionsColumnWidth),
        ],
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel({
    required this.label,
    required this.sorted,
    required this.descending,
    required this.onTap,
    this.alignEnd = false,
  });

  final String label;
  final bool sorted;
  final bool descending;
  final bool alignEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = sorted ? colors.textPrimary : colors.textTertiary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (sorted) ...[
              const SizedBox(width: 4),
              Icon(
                descending
                    ? PhosphorIconsRegular.caretDown
                    : PhosphorIconsRegular.caretUp,
                size: 12,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of the directory listing: its icon, name, size and modified time,
/// a selection checkmark once [selectionMode] is on, and the `⋮` actions menu
/// otherwise.
///
/// With [columns] it is one line of a table under [SftpColumnHeader] - size
/// and date each in a column of their own - instead of a name with a caption
/// under it, with no checkmark: there a click selects and the highlight is
/// the mark. [isCursor] outlines the row the keyboard is on.
class SftpFileRow extends StatelessWidget {
  const SftpFileRow({
    super.key,
    required this.item,
    this.columns,
    this.isCursor = false,
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
  final SftpColumns? columns;
  final bool isCursor;

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
    final columns = this.columns;
    if (columns != null) {
      return _buildColumns(context, columns, isDir: isDir, isUp: isUp);
    }

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

  Widget _buildColumns(
    BuildContext context,
    SftpColumns columns, {
    required bool isDir,
    required bool isUp,
  }) {
    final colors = context.colors;
    final accent = colors.primary;
    final detail = TextStyle(
      color: colors.textSecondary,
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final Widget icon;
    if (isProbing) {
      icon = SizedBox.square(
        dimension: _kColumnIconSize,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
    } else if (isUp || isDir) {
      icon = Icon(
        isUp ? PhosphorIconsFill.folderOpen : PhosphorIconsFill.folder,
        color: accent,
        size: _kColumnIconSize,
      );
    } else {
      icon = buildFileIcon(
        item.filename,
        size: _kColumnIconSize,
        fallbackColor: colors.textSecondary,
      );
    }

    return Material(
      color: isSelected ? accent.withValues(alpha: 0.12) : accent.invisible,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: kSftpRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: _kRowInset),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: isCursor
                  ? accent.withValues(alpha: 0.55)
                  : accent.invisible,
            ),
          ),
          child: Row(
            children: [
              icon,
              const SizedBox(width: _kColumnIconGap),
              Expanded(
                child: Text(
                  item.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (columns.size) ...[
                const SizedBox(width: _kColumnGap),
                SizedBox(
                  width: _kSizeColumnWidth,
                  child: Text(
                    isUp || isDir ? '' : formatFileSize(item.attr.size),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    style: detail,
                  ),
                ),
              ],
              if (columns.modified) ...[
                const SizedBox(width: _kColumnGap),
                SizedBox(
                  width: _kModifiedColumnWidth,
                  child: Text(
                    isUp ? '' : _formatModifiedColumn(item.attr.modifyTime),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: detail,
                  ),
                ),
              ],
              SizedBox(
                width: _kActionsColumnWidth,
                child: isUp
                    ? null
                    : SftpFileActionsMenu(
                        item: item,
                        probe: probe,
                        runProbe: runProbe,
                        opener: opener,
                        copyAvailable: copyAvailable,
                        onAction: onAction,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

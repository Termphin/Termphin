import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../utils/file_type.dart';
import '../../utils/text_sniffer.dart';
import '../ui/app_dropdown.dart';

/// What a row's `⋮` menu offers - directory and file entries share the shape,
/// just not every entry.
enum SftpFileAction {
  openEditor,
  preview,
  download,
  copyPath,
  rename,
  copyTo,
  moveTo,
  duplicate,
  delete,
}

/// The `⋮` trigger for one row. [opener] lets a tap on a file that turns out
/// to be binary pop this same menu open, rather than keeping a second,
/// separate presentation of the same actions around for that one case.
class SftpFileActionsMenu extends StatelessWidget {
  const SftpFileActionsMenu({
    super.key,
    required this.item,
    required this.probe,
    required this.runProbe,
    required this.opener,
    required this.copyAvailable,
    required this.onAction,
  });

  final SftpName item;
  final TextProbe? probe;
  final Future<TextProbe?> Function() runProbe;
  final ValueNotifier<Object?> opener;
  final bool copyAvailable;
  final ValueChanged<SftpFileAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTertiary = colors.textPrimary.withValues(alpha: 0.58);
    final isDirectory = item.attr.isDirectory;
    final isImage = !isDirectory && fileTypeOf(item.filename) == FileKind.image;

    return AppActionDropdown<SftpFileAction>(
      iconSize: 18,
      iconColor: textTertiary,
      buttonSize: 34,
      width: 240,
      openDropdownListenable: opener,
      onSelected: onAction,
      items: [
        if (!isDirectory) ...[
          DropdownItem(
            value: SftpFileAction.openEditor,
            intrinsicHeight: true,
            child: _EditorActionTile(
              probe: probe,
              runProbe: runProbe,
              textColor: colors.textPrimary,
              secondaryColor: textTertiary,
            ),
          ),
          if (isImage)
            DropdownItem(
              value: SftpFileAction.preview,
              intrinsicHeight: true,
              child: AppDropdownItem(
                icon: PhosphorIconsFill.image,
                label: t.sftp.preview,
              ),
            ),
          DropdownItem(
            value: SftpFileAction.download,
            intrinsicHeight: true,
            child: AppDropdownItem(
              icon: PhosphorIconsFill.downloadSimple,
              label: t.sftp.download,
            ),
          ),
        ],
        DropdownItem(
          value: SftpFileAction.copyPath,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.copy,
            label: t.sftp.copyPath,
          ),
        ),
        DropdownItem(
          value: SftpFileAction.rename,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.pencilSimple,
            label: t.common.rename,
          ),
        ),
        if (copyAvailable)
          DropdownItem(
            value: SftpFileAction.copyTo,
            intrinsicHeight: true,
            child: AppDropdownItem(
              icon: PhosphorIconsFill.folders,
              label: t.sftp.copyTo,
            ),
          ),
        DropdownItem(
          value: SftpFileAction.moveTo,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.arrowSquareRight,
            label: t.sftp.moveTo,
          ),
        ),
        if (copyAvailable)
          DropdownItem(
            value: SftpFileAction.duplicate,
            intrinsicHeight: true,
            child: AppDropdownItem(
              icon: PhosphorIconsFill.copySimple,
              label: t.common.duplicate,
            ),
          ),
        DropdownItem(
          value: SftpFileAction.delete,
          intrinsicHeight: true,
          child: AppDropdownItem(
            icon: PhosphorIconsFill.trash,
            label: t.common.delete,
            color: colors.error,
          ),
        ),
      ],
    );
  }
}

/// The "open in editor" row of the file actions menu. What it says depends on
/// what the file's own bytes turned out to be, not on its name - purely
/// presentational, since selecting it always opens the editor either way; the
/// enclosing dropdown is what turns a tap on this row into that action.
class _EditorActionTile extends StatefulWidget {
  const _EditorActionTile({
    required this.probe,
    required this.runProbe,
    required this.textColor,
    required this.secondaryColor,
  });

  final TextProbe? probe;
  final Future<TextProbe?> Function() runProbe;
  final Color textColor;
  final Color secondaryColor;

  @override
  State<_EditorActionTile> createState() => _EditorActionTileState();
}

class _EditorActionTileState extends State<_EditorActionTile> {
  TextProbe? _probe;
  bool _probing = false;

  /// Deferred a frame: [widget.runProbe] reaches into the parent screen's
  /// setState before its first await, and this tile mounts while the
  /// dropdown's own overlay is building - calling into an unrelated
  /// subtree's setState from inside that build trips "setState during
  /// build".
  @override
  void initState() {
    super.initState();
    _probe = widget.probe;
    if (_probe == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startProbe();
      });
    }
  }

  Future<void> _startProbe() async {
    setState(() => _probing = true);
    final probe = await widget.runProbe();
    if (!mounted) return;
    setState(() {
      _probe = probe;
      _probing = false;
    });
  }

  /// The spinner stands in for the icon so the row keeps the geometry every
  /// other menu entry is drawn with while the probe runs.
  @override
  Widget build(BuildContext context) {
    final probe = _probe;
    if (_probing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.secondaryColor,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                t.sftp.checkingFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.secondaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (probe == null) return const SizedBox.shrink();

    return AppDropdownItem(
      icon: probe.isText
          ? PhosphorIconsFill.pencilSimple
          : PhosphorIconsFill.warningCircle,
      label: probe.isText ? t.sftp.openInEditor : t.sftp.openAsText,
      color: probe.isText ? widget.textColor : widget.secondaryColor,
    );
  }
}

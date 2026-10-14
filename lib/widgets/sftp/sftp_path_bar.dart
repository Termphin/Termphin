import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/sftp/remote_path.dart';
import '../../theme/theme.dart';
import '../../utils/sftp_path.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/context_bar.dart';

/// The breadcrumb row above the listing: where the current folder is, and the
/// refresh, sort and hidden-files controls. Tapping the path turns it into a
/// text field so a path can be typed or pasted in directly.
class SftpPathBar extends StatefulWidget {
  const SftpPathBar({
    super.key,
    required this.currentPath,
    required this.refreshing,
    required this.showHidden,
    required this.onNavigateToSegment,
    required this.onNavigateToRoot,
    required this.onPathSubmitted,
    required this.onRefresh,
    required this.onSort,
    required this.onToggleHidden,
    required this.onEditingChanged,
    this.trailing,
  });

  final String currentPath;
  final bool refreshing;
  final bool showHidden;
  final ValueChanged<int> onNavigateToSegment;
  final VoidCallback onNavigateToRoot;

  /// The trimmed text the user typed or pasted, still in display form.
  final ValueChanged<String> onPathSubmitted;
  final VoidCallback onRefresh;
  final VoidCallback onSort;
  final VoidCallback onToggleHidden;
  final ValueChanged<bool> onEditingChanged;

  /// The "+" menu, kept here rather than floating over the list - down there
  /// it covered the last row and the overflow button on it, since the list
  /// has no bottom padding.
  final Widget? trailing;

  @override
  State<SftpPathBar> createState() => _SftpPathBarState();
}

class _SftpPathBarState extends State<SftpPathBar> {
  bool _editingPath = false;
  late final TextEditingController _pathController;
  late final FocusNode _pathFocusNode;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    _pathFocusNode = FocusNode();
    _pathFocusNode.addListener(() {
      if (!_pathFocusNode.hasFocus && _editingPath) {
        setState(() => _editingPath = false);
        _pathController.text = widget.currentPath;
        widget.onEditingChanged(false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SftpPathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPath != oldWidget.currentPath) {
      _pathController.text = widget.currentPath;
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    _pathFocusNode.dispose();
    super.dispose();
  }

  /// Pull to refresh also works over the list below, though nothing on
  /// screen says so. [trailing] comes last, so the one action that writes
  /// to the server sits apart from the two that only change what is on
  /// screen.
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = colors.primary;
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    final textTertiary = textPrimary.withValues(alpha: 0.58);
    final isWindowsPath = isWindowsSftpPath(widget.currentPath);
    final segments = remotePathSegments(widget.currentPath);

    Widget tool({
      required IconData icon,
      required Color color,
      required VoidCallback? onTap,
      String? tooltip,
    }) {
      final button = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 40,
          child: Icon(icon, color: color, size: 20),
        ),
      );
      return tooltip == null
          ? button
          : Tooltip(message: tooltip, child: button);
    }

    return Container(
      height: ContextBar.height,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
      ),
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Row(
        children: [
          tool(
            icon: PhosphorIconsFill.folderOpen,
            color: accent,
            onTap: widget.onNavigateToRoot,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _editingPath
                ? TextField(
                    controller: _pathController,
                    focusNode: _pathFocusNode,
                    autofocus: true,
                    onTapOutside: (_) => _pathFocusNode.unfocus(),
                    style: colors.monoStyle.copyWith(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (value) {
                      setState(() => _editingPath = false);
                      widget.onEditingChanged(false);
                      widget.onPathSubmitted(value.trim());
                    },
                  )
                : GestureDetector(
                    onTap: () {
                      _pathController.text = sftpPathToDisplay(
                        widget.currentPath,
                      );
                      setState(() => _editingPath = true);
                      widget.onEditingChanged(true);
                      Future.delayed(
                        Duration.zero,
                        () => _pathFocusNode.requestFocus(),
                      );
                    },
                    onLongPress: () => copyToClipboard(
                      context,
                      sftpPathToDisplay(widget.currentPath),
                      message: t.sftp.pathCopied,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        children: [
                          for (var i = 0; i < segments.length; i++) ...[
                            if (i > 0)
                              Text(
                                isWindowsPath ? r' \ ' : ' / ',
                                style: colors.monoStyle.copyWith(
                                  color: textTertiary,
                                  fontSize: 14,
                                ),
                              ),
                            GestureDetector(
                              onTap: () => widget.onNavigateToSegment(i),
                              child: Text(
                                segments[i],
                                style: colors.monoStyle.copyWith(
                                  color: i == segments.length - 1
                                      ? textPrimary
                                      : textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          tool(
            icon: PhosphorIconsFill.arrowClockwise,
            color: textTertiary,
            tooltip: t.common.refresh,
            onTap: widget.refreshing ? null : widget.onRefresh,
          ),
          tool(
            icon: PhosphorIconsFill.sortAscending,
            color: textTertiary,
            onTap: widget.onSort,
          ),
          tool(
            icon: widget.showHidden
                ? PhosphorIconsFill.eye
                : PhosphorIconsFill.eyeSlash,
            color: widget.showHidden ? accent : textTertiary,
            onTap: widget.onToggleHidden,
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

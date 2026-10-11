import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import '../../utils/platform_info.dart';

/// One row of a right-click menu. Null in a list of entries draws a divider.
class ContextMenuEntry {
  const ContextMenuEntry({
    required this.label,
    required this.onSelected,
    this.icon,
    this.shortcut,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;

  /// The keys that do the same, printed at the row's end.
  final String? shortcut;
  final bool destructive;
  final bool enabled;
}

/// Opens [entries] at [globalPosition], the way every desktop opens a menu on
/// a right click: under the pointer, closed by Esc or a click elsewhere.
Future<void> showAppContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<ContextMenuEntry?> entries,
}) async {
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  if (overlay == null) return;
  final at = overlay.globalToLocal(globalPosition);
  final colors = context.colors;
  final index = await showMenu<int>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(at.dx, at.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      for (var i = 0; i < entries.length; i++)
        if (entries[i] case final entry?)
          PopupMenuItem<int>(
            value: i,
            enabled: entry.enabled,
            height: 36,
            child: Row(
              children: [
                if (entry.icon != null) ...[
                  Icon(
                    entry.icon,
                    size: 16,
                    color: entry.destructive
                        ? colors.error
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    entry.label,
                    style: colors.uiStyle.copyWith(
                      color: entry.destructive
                          ? colors.error
                          : colors.textPrimary,
                    ),
                  ),
                ),
                if (entry.shortcut != null) ...[
                  const SizedBox(width: 24),
                  Text(
                    entry.shortcut!,
                    style: colors.uiSmall.copyWith(color: colors.textTertiary),
                  ),
                ],
              ],
            ),
          )
        else
          const PopupMenuDivider(height: 8),
    ],
  );
  if (index == null) return;
  entries[index]?.onSelected();
}

/// Gives [child] a right-click menu on a desktop. On a phone it is [child]
/// as it was: a long press there already selects, and a second gesture on
/// the same row would only fight it.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    required this.entries,
    required this.child,
  });

  /// Built when the menu opens, so it reflects the row as it is then.
  final List<ContextMenuEntry?> Function() entries;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) => showAppContextMenu(
        context,
        globalPosition: details.globalPosition,
        entries: entries(),
      ),
      child: child,
    );
  }
}

/// Whether the click being handled adds to a selection rather than opening
/// what was clicked: Ctrl held, or Cmd on a Mac - the desktop's long press.
bool get selectionModifierPressed {
  if (!isDesktopPlatform) return false;
  final keyboard = HardwareKeyboard.instance;
  return isMacOSPlatform ? keyboard.isMetaPressed : keyboard.isControlPressed;
}

/// Whether Shift is held, which extends a selection to the clicked row.
bool get rangeModifierPressed =>
    isDesktopPlatform && HardwareKeyboard.instance.isShiftPressed;

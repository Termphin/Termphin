import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import '../ui/action_dock_tile.dart';
import 'terminal_scheme_theme.dart';

/// One action offered by the command palette grid - upload, paste, insert
/// snippet, or anything else a screen wants reachable from the same anchored
/// menu the floating dock's button opens.
class SpotlightTool {
  const SpotlightTool({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  /// Greyed out rather than left off the panel, so a tool that needs
  /// something the current session doesn't have (a persistent-session agent,
  /// say) still shows what tapping it would explain, rather than looking
  /// like it was never offered.
  final bool enabled;
}

/// Closes the open menu, if there is one.
VoidCallback? _dismissOpenMenu;

/// Closes the action dock's menu if it is open, and says whether it was -
/// back spends itself on the menu before it reaches the screen.
bool dismissActionDockMenu() {
  final dismiss = _dismissOpenMenu;
  if (dismiss == null) return false;
  dismiss();
  return true;
}

/// Beyond this many rows the panel stops growing and scrolls instead. Under
/// it, it is exactly as tall as its rows need - no padding out to a fixed
/// size, and nothing to scroll.
const int _maxRows = 3;

/// Small menu anchored to wherever the floating action dock's button
/// currently is.
///
/// An [OverlayEntry] rather than a dialog route on purpose: a route installs
/// its own focus scope and becomes the primary one, which pulls focus off
/// the terminal and drops the keyboard the moment this opens. An overlay
/// entry touches no focus at all - the terminal keeps its keyboard up
/// throughout, and the panel simply floats over it.
///
/// Being no route, it is also invisible to back, so whoever handles back for
/// the terminal asks [dismissActionDockMenu] first - see
/// [TerminalScreenState.handleBack].
///
/// Wrapped in [TerminalSchemeTheme]: the root overlay is outside the
/// terminal, and an entry inherits nothing from where it was opened, so
/// without it the panel would come up in app colours.
Future<void> showActionDockMenu(
  BuildContext context, {
  required Rect anchorRect,
  required List<SpotlightTool> tools,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late OverlayEntry entry;

  void dismiss() {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete();
    if (_dismissOpenMenu == dismiss) _dismissOpenMenu = null;
  }

  _dismissOpenMenu?.call();
  _dismissOpenMenu = dismiss;

  entry = OverlayEntry(
    builder: (ctx) => TerminalSchemeTheme(
      child: _ActionDockMenu(
        anchorRect: anchorRect,
        tools: tools,
        onDismiss: dismiss,
      ),
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

/// The panel grows out of the button and covers it, rather than sitting
/// beside it: the corner nearest the middle of the screen is pinned to the
/// button's matching corner, so it unfolds inward - in position and in the
/// scale-in animation - with the button underneath. Its width is explicit,
/// or the `Wrap` inside would lay every tile in one wide row instead of
/// wrapping to three; its height is what the rows need, up to a ceiling
/// past which it scrolls.
class _ActionDockMenu extends StatelessWidget {
  const _ActionDockMenu({
    required this.anchorRect,
    required this.tools,
    required this.onDismiss,
  });

  final Rect anchorRect;
  final List<SpotlightTool> tools;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;
    final rows = (tools.length / kPaletteColumns).ceil().clamp(1, 99);
    final wantedHeight = palettePanelHeight(rows);
    final maxHeight = palettePanelHeight(_maxRows);
    final panelHeight = wantedHeight < maxHeight ? wantedHeight : maxHeight;

    final anchorCenterX = anchorRect.left + anchorRect.width / 2;
    final anchorCenterY = anchorRect.top + anchorRect.height / 2;
    final opensLeft = anchorCenterX > screen.width / 2;
    final opensAbove = anchorCenterY > screen.height / 2;

    double left = opensLeft
        ? anchorRect.right - kPalettePanelWidth
        : anchorRect.left;
    left = left.clamp(12.0, screen.width - kPalettePanelWidth - 12.0);

    double top = opensAbove ? anchorRect.bottom - panelHeight : anchorRect.top;
    top = top.clamp(
      safePadding.top + 12.0,
      screen.height - safePadding.bottom - panelHeight - 12.0,
    );

    final panel = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: kPalettePanelWidth,
          child: TweenAnimationBuilder<double>(
            duration: AppTheme.motionFast,
            curve: Curves.easeOut,
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(
                alignment: Alignment(opensLeft ? 1 : -1, opensAbove ? 1 : -1),
                scale: 0.92 + 0.08 * value,
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ActionDockPanel(
                child: SingleChildScrollView(
                  physics: wantedHeight <= maxHeight
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: Wrap(
                    spacing: kPaletteTileSpacing,
                    runSpacing: kPaletteTileSpacing,
                    children: [
                      for (final tool in tools)
                        ActionDockTile(
                          icon: tool.icon,
                          label: tool.label,
                          dimmed: !tool.enabled,
                          onTap: () {
                            onDismiss();
                            HapticFeedback.selectionClick();
                            tool.onSelect();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return panel;
  }
}

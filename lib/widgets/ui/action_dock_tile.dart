import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'two_line_label.dart';

/// Metrics shared by the command palette itself and the editor for it in
/// Settings, so the editor is a literal preview of the thing it edits rather
/// than a list that merely describes it.
const double kPaletteTileWidth = 76;
const double kPaletteTileHeight = 68;
const double kPaletteTileSpacing = 6;
const double kPalettePanelPadding = 8;
const int kPaletteColumns = 3;

/// The panel's 1px border sits inside whatever size it is given, so both of
/// these count it - miss it and the last column no longer fits, dropping a
/// three-tile row to two.
const double _panelBorder = 1;

/// Outer width of a three-column panel.
const double kPalettePanelWidth =
    _panelBorder * 2 +
    kPalettePanelPadding * 2 +
    kPaletteColumns * kPaletteTileWidth +
    (kPaletteColumns - 1) * kPaletteTileSpacing;

/// Outer height a panel of [rows] rows comes out to.
double palettePanelHeight(int rows) =>
    _panelBorder * 2 +
    kPalettePanelPadding * 2 +
    rows * kPaletteTileHeight +
    (rows - 1) * kPaletteTileSpacing;

/// One command palette entry: icon over a label that always occupies two
/// lines, so every tile is the same height whether its label wraps or not.
class ActionDockTile extends StatelessWidget {
  const ActionDockTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.dimmed = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Hidden from the palette - shown in the editor's tray, greyed out.
  final bool dimmed;

  /// Drag currently hovering this slot.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final iconColor = dimmed
        ? context.colors.textTertiary
        : context.colors.primary;
    final textColor = dimmed
        ? context.colors.textTertiary
        : context.colors.textSecondary;
    return SizedBox(
      width: kPaletteTileWidth,
      height: kPaletteTileHeight,
      child: Material(
        color: highlighted
            ? context.colors.primary.withValues(alpha: 0.12)
            : context.colors.primary.invisible,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: AppTheme.icon20, color: iconColor),
              const SizedBox(height: AppTheme.space4),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space2,
                ),
                child: TwoLineLabel(
                  text: label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppTheme.font10,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The panel the tiles sit on - same surface, border and radius wherever it
/// appears.
class ActionDockPanel extends StatelessWidget {
  const ActionDockPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: context.colors.surfaceBorder),
        ),
        padding: const EdgeInsets.all(kPalettePanelPadding),
        child: child,
      ),
    );
  }
}

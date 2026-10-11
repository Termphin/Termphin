import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';

/// How a selectable card paints, so machines, keys and snippets agree on what
/// "selected" looks like.
///
/// The tint is blended over the card's own surface rather than swapped for
/// [AppColors.primaryHighlight]: in the dark palette that colour sits below
/// the card, and a selected card read as a hole in the list.
abstract final class SelectionStyle {
  static Color fill(
    BuildContext context,
    Color base, {
    required bool selected,
  }) {
    if (!selected) return base;
    final colors = context.colors;
    return Color.alphaBlend(
      colors.primary.withValues(alpha: colors.isDark ? 0.16 : 0.10),
      base,
    );
  }

  static BorderSide side(BuildContext context, {required bool selected}) =>
      selected
      ? BorderSide(color: context.colors.primary, width: 1.5)
      : BorderSide(color: context.colors.surfaceBorder);
}

/// Stands in for a row's avatar while the row is selected: a filled check in
/// the same circle, so the row keeps its shape and the mark lands where the
/// eye already is.
///
/// Without a [child] (a key has no avatar) an unselected row shows an empty
/// ring instead, so the tap target reads as a checkbox.
class SelectionCheck extends StatelessWidget {
  const SelectionCheck({
    super.key,
    required this.selected,
    required this.size,
    this.child,
  });

  final bool selected;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Widget current;
    if (selected) {
      current = Container(
        key: const ValueKey('checked'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          PhosphorIconsRegular.check,
          size: size * 0.5,
          color: colors.onPrimary,
        ),
      );
    } else if (child case final avatar?) {
      current = KeyedSubtree(key: const ValueKey('avatar'), child: avatar);
    } else {
      current = Container(
        key: const ValueKey('ring'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.surfaceBorderStrong, width: 2),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: AppTheme.interactiveDuration,
        switchInCurve: AppTheme.interactiveCurve,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: current,
      ),
    );
  }
}

/// Lays a [SelectionActionBar] over a list, sliding it in while [bar] is
/// non-null and out again once the selection is cleared.
///
/// Floating, not pinned under the list: a strip stacked on the bottom nav
/// read as a second, foreign nav bar. The list keeps its last row reachable
/// by reserving [SelectionActionBar.reservedHeight] at its end while
/// selecting.
class SelectionActionHost extends StatelessWidget {
  const SelectionActionHost({super.key, required this.child, this.bar});

  final Widget child;
  final SelectionActionBar? bar;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: AppTheme.motionSlow,
            switchInCurve: AppTheme.interactiveCurve,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: bar ?? const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// The actions over a list while rows are selected.
///
/// Machines, keys and snippets all carry a group and all delete the same way,
/// so the three screens share this rather than each growing its own bar and
/// drifting on which action sits where. The actions are drawn the way the
/// bottom nav draws its tabs - icon over a short label - so the bar belongs
/// to the same family instead of being a stock contextual toolbar.
///
/// Wraps its content in a transparent `Material`: the actions' ink needs a
/// `Material` above the bar's own fill to show.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onMove,
    required this.onDelete,
    required this.onClear,
    this.onSelectAll,
  });

  /// What a list leaves free at its end so the bar never covers its last row.
  static const double reservedHeight = 96;

  final int count;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  /// Null when everything is already selected, which greys the button out
  /// rather than offering an action that would do nothing.
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final empty = count == 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: colors.surfaceBorderStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: colors.isDark ? 0.3 : 0.08,
                ),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                IconButton(
                  tooltip: t.selection.clear,
                  onPressed: onClear,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.surfaceOffset,
                    foregroundColor: colors.textSecondary,
                    fixedSize: const Size.square(40),
                    minimumSize: const Size.square(40),
                  ),
                  icon: const Icon(PhosphorIconsRegular.x, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppTheme.motionFast,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      t.selection.countSelected(n: count, count: count),
                      key: ValueKey(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: colors.itemTitle,
                    ),
                  ),
                ),
                _BarAction(
                  icon: PhosphorIconsRegular.checks,
                  label: t.selection.all,
                  tooltip: t.selection.selectAll,
                  onPressed: onSelectAll,
                ),
                _BarAction(
                  icon: PhosphorIconsRegular.folderSimple,
                  label: t.selection.move,
                  tooltip: t.selection.moveToGroup,
                  onPressed: empty ? null : onMove,
                ),
                _BarAction(
                  icon: PhosphorIconsRegular.trash,
                  label: t.common.delete,
                  tooltip: t.common.delete,
                  color: colors.error,
                  onPressed: empty ? null : onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    final tint = (color ?? colors.textPrimary).withValues(
      alpha: enabled ? 1 : 0.35,
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                }
              : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: SizedBox(
            width: 60,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: tint),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.uiSmall.copyWith(fontSize: 11, color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

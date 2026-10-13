import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import 'context_bar.dart';

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

/// Puts a [SelectionActionBar] under a list, sliding it up from the bottom
/// edge while [bar] is non-null and back down once the selection is cleared.
///
/// Docked rather than floating: it pushes the list up instead of covering
/// it, so nothing needs to be reserved at the list's end, and it is the same
/// strip the file browser and the transfer bar use. At the bottom, within
/// reach of the thumb that made the selection.
class SelectionActionHost extends StatelessWidget {
  const SelectionActionHost({super.key, required this.child, this.bar});

  final Widget child;
  final SelectionActionBar? bar;

  @override
  Widget build(BuildContext context) {
    final instant = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        Expanded(child: child),
        AnimatedSwitcher(
          duration: instant ? Duration.zero : AppTheme.motionSlow,
          switchInCurve: AppTheme.interactiveCurve,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => ClipRect(
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
          child: bar == null
              ? const SizedBox(width: double.infinity)
              : KeyedSubtree(
                  key: const ValueKey('bar'),
                  child: SafeArea(top: false, child: bar!),
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
/// drifting on which action sits where. It is a [ContextBar], the same strip
/// the file browser selects with.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onMove,
    required this.onDelete,
    required this.onClear,
    this.onSelectAll,
  });

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
    return ContextBar(
      selection: true,
      atBottom: true,
      leading: ContextBarClose(tooltip: t.selection.clear, onPressed: onClear),
      title: t.selection.countSelected(n: count, count: count),
      actions: [
        ContextBarAction(
          icon: PhosphorIconsRegular.checks,
          label: t.selection.selectAll,
          onPressed: onSelectAll,
        ),
        ContextBarAction(
          icon: PhosphorIconsRegular.folderSimple,
          label: t.selection.moveToGroup,
          onPressed: empty ? null : onMove,
        ),
        ContextBarAction(
          icon: PhosphorIconsRegular.trash,
          label: t.common.delete,
          color: colors.error,
          onPressed: empty ? null : onDelete,
        ),
      ],
    );
  }
}

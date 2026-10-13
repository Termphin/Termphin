import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import 'app_dropdown.dart';
import 'selection_action_bar.dart';

/// One action on a [ContextBar].
class ContextBarAction {
  const ContextBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;

  /// What the action is called in the overflow menu, and its tooltip unless
  /// [tooltip] says otherwise.
  final String label;

  /// Why the action cannot run, when it cannot.
  final String? tooltip;

  /// Null greys the action out.
  final VoidCallback? onPressed;
  final Color? color;
}

/// The strip that sits under a screen's header, or above its bottom edge,
/// while something is going on: rows are selected, or files are moving.
///
/// Docked to the full width rather than floating over the content, so the
/// selection bars and the transfer bar read as one family wherever they
/// show. [selection] tints it with the colour a selected card wears, which
/// is how the mode announces itself.
///
/// Actions that do not fit the width move into a "More" menu from the end,
/// so a split pane gets the same bar with fewer buttons on it.
class ContextBar extends StatelessWidget {
  const ContextBar({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.menu = const [],
    this.trailing,
    this.progress,
    this.progressColor,
    this.selection = false,
    this.atBottom = false,
    this.onTap,
    this.semanticLabel,
  });

  static const height = 48.0;

  /// Width of each action button, and of the leading slot.
  static const _slot = 44.0;

  /// What the title keeps however many actions there are.
  static const _minTitleWidth = 104.0;

  final Widget leading;
  final String title;
  final String? subtitle;

  /// Shown on the bar while they fit, in order.
  final List<ContextBarAction> actions;

  /// Always in the "More" menu, after any action pushed there for room.
  final List<ContextBarAction> menu;

  /// Drawn after the actions, such as a caret on a bar that expands.
  final Widget? trailing;

  /// 0..1 drawn as a thin line along the bottom edge; null draws none.
  final double? progress;
  final Color? progressColor;
  final bool selection;

  /// Docked to the bottom edge instead of under a header: the hairline goes
  /// on top, where the bar meets the content.
  final bool atBottom;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = SelectionStyle.fill(
      context,
      colors.surfaceCard,
      selected: selection,
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _content(context, constraints.maxWidth),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: atBottom ? 0 : null,
                  bottom: atBottom ? null : 0,
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: colors.surfaceBorder,
                  ),
                ),
                if (progress case final value?)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ProgressLine(
                      value: value,
                      color: progressColor ?? colors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, double width) {
    final colors = context.colors;
    final (inline, overflow) = _split(width);

    return Row(
      children: [
        SizedBox(
          width: _slot + 4,
          child: Center(child: leading),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: AppTheme.motionFast,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  title,
                  key: ValueKey(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.uiStyle.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (subtitle case final text?)
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.uiSmall.copyWith(
                    color: colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
        for (final action in inline) _ActionButton(action: action),
        if (overflow.isNotEmpty) _OverflowMenu(actions: overflow),
        ?trailing,
        if (trailing == null && inline.isEmpty && overflow.isEmpty)
          const SizedBox(width: 8),
        if (inline.isNotEmpty || overflow.isNotEmpty) const SizedBox(width: 4),
      ],
    );
  }

  /// The actions that fit on the bar, and what goes into the menu.
  (List<ContextBarAction>, List<ContextBarAction>) _split(double width) {
    final reserved =
        _slot + 4 + _minTitleWidth + (trailing == null ? 0 : _slot) + 4;
    final room = ((width - reserved) / _slot).floor();
    if (actions.length <= room - (menu.isEmpty ? 0 : 1)) {
      return (actions, menu);
    }
    final fit = (room - 1).clamp(0, actions.length);
    return (actions.sublist(0, fit), [...actions.sublist(fit), ...menu]);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final ContextBarAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onPressed = action.onPressed;
    return SizedBox.square(
      dimension: ContextBar._slot,
      child: IconButton(
        tooltip: action.tooltip ?? action.label,
        onPressed: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed();
              },
        color: action.color ?? colors.textSecondary,
        disabledColor: (action.color ?? colors.textSecondary).withValues(
          alpha: 0.35,
        ),
        icon: Icon(action.icon, size: 20),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.actions});

  final List<ContextBarAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final enabled = [
      for (final action in actions)
        if (action.onPressed != null) action,
    ];
    return AppActionDropdown<int>(
      iconSize: 20,
      iconColor: colors.textSecondary,
      buttonSize: ContextBar._slot,
      width: 220,
      tooltip: t.selection.more,
      onSelected: (index) => enabled[index].onPressed!(),
      items: [
        for (final (index, action) in enabled.indexed)
          DropdownItem(
            value: index,
            intrinsicHeight: true,
            child: AppDropdownItem(
              icon: action.icon,
              label: action.label,
              color: action.color,
            ),
          ),
      ],
    );
  }
}

/// The bar's progress, eased from one value to the next rather than jumping.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.motionSlow,
      curve: Curves.easeOut,
      builder: (context, value, _) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value,
          child: SizedBox(height: 2, child: ColoredBox(color: color)),
        ),
      ),
    );
  }
}

/// A small ring with the percentage inside, for the leading slot of a bar
/// that tracks progress.
class ContextBarProgressRing extends StatelessWidget {
  const ContextBarProgressRing({
    super.key,
    required this.value,
    required this.color,
  });

  /// 0..1, or null while it cannot be known - the ring spins then.
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = this.value;
    return SizedBox.square(
      dimension: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: value ?? 0),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppTheme.motionSlow,
              curve: Curves.easeOut,
              builder: (context, eased, _) => CircularProgressIndicator(
                value: value == null ? null : eased,
                strokeWidth: 2.5,
                backgroundColor: colors.surfaceOffset,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          if (value != null)
            Text(
              '${(value * 100).floor()}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// The leading close button of a selection bar.
class ContextBarClose extends StatelessWidget {
  const ContextBarClose({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: context.colors.textPrimary,
      icon: const Icon(PhosphorIconsRegular.x, size: 20),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// The app's single tag chip.
///
/// Every tag - the filter strips on machines, snippets and the snippet
/// spotlight, and the read-only tags on cards - uses this one look.
/// [TagChip.display] is the non-interactive variant for cards, slightly
/// smaller so a handful of them doesn't dominate the card.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    required this.selected,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.solid = false,
    this.minHeight,
  }) : _display = false;

  /// Read-only chip for tags shown on cards.
  const TagChip.display({super.key, required this.label, this.leading})
    : selected = true,
      trailing = null,
      onTap = null,
      onLongPress = null,
      solid = false,
      minHeight = null,
      _display = true;

  final String label;
  final bool selected;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Selected reads as a solid accent fill rather than a tint, for a chip
  /// that toggles a mode (a held modifier key) rather than filters a list.
  final bool solid;

  /// After the label, e.g. a clear button.
  final Widget? trailing;

  /// A taller chip for a toggle the thumb hits often; the label stays centred.
  final double? minHeight;

  final bool _display;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filled = solid && selected;
    final radius = BorderRadius.circular(AppTheme.radiusPill);
    final tappable = onTap != null || onLongPress != null;
    final padding = EdgeInsets.symmetric(
      horizontal: _display ? AppTheme.space10 : AppTheme.space12,
      vertical: _display ? AppTheme.space4 : AppTheme.space6,
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppTheme.space6),
        ],
        Text(
          label,
          style: colors.uiSmall.copyWith(
            fontSize: _display ? AppTheme.font11 : AppTheme.font12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: filled
                ? colors.onPrimary
                : selected
                ? colors.primary
                : colors.textSecondary,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppTheme.space4),
          trailing!,
        ],
      ],
    );
    final inner = Padding(
      padding: padding,
      child: minHeight == null
          ? content
          : Center(widthFactor: 1, heightFactor: 1, child: content),
    );
    return AnimatedContainer(
      duration: AppTheme.interactiveDuration,
      constraints: minHeight == null
          ? null
          : BoxConstraints(minHeight: minHeight!),
      decoration: BoxDecoration(
        color: filled
            ? colors.primary
            : selected
            ? colors.primaryHighlight
            : colors.surfaceCard,
        borderRadius: radius,
        border: Border.all(
          color: filled
              ? colors.primary
              : selected
              ? colors.primaryMuted
              : colors.surfaceBorder,
        ),
      ),
      child: !tappable
          ? inner
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                onLongPress: onLongPress,
                child: inner,
              ),
            ),
    );
  }
}

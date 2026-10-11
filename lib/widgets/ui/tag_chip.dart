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
    this.onTap,
    this.onLongPress,
  }) : _display = false;

  /// Read-only chip for tags shown on cards.
  const TagChip.display({super.key, required this.label, this.leading})
    : selected = true,
      onTap = null,
      onLongPress = null,
      _display = true;

  final String label;
  final bool selected;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool _display;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: AppTheme.interactiveDuration,
      padding: EdgeInsets.symmetric(
        horizontal: _display ? 10 : 12,
        vertical: _display ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: selected
            ? context.colors.primaryHighlight
            : context.colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: selected
              ? context.colors.primaryMuted
              : context.colors.surfaceBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(
            label,
            style: context.colors.uiSmall.copyWith(
              fontSize: _display ? 11 : 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? context.colors.primary
                  : context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return chip;
    return GestureDetector(onTap: onTap, onLongPress: onLongPress, child: chip);
  }
}

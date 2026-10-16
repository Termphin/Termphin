import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Tone for the empty state panel: whether it's neutral or an error state.
enum EmptyStateTone {
  /// Neutral: icon colour textSecondary, frame fill surfaceCard.
  neutral,

  /// Error: icon colour error, frame fill errorHighlight, no border.
  error,
}

/// Full-height empty state for a screen with nothing to list yet: framed
/// icon, headline, optional explanation and optional call to action.
///
/// Shared so every screen's "nothing here" reads the same - see
/// [EmptyStateHint] for the compact in-list variant.
class EmptyStatePanel extends StatelessWidget {
  const EmptyStatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.tone = EmptyStateTone.neutral,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final EmptyStateTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isError = tone == EmptyStateTone.error;
    final frameSize = compact ? 44.0 : 58.0;
    final iconSize = compact ? AppTheme.icon22 : AppTheme.icon26;
    final outerPadding = compact
        ? const EdgeInsets.all(AppTheme.space24)
        : const EdgeInsets.fromLTRB(
            AppTheme.space32,
            AppTheme.space48,
            AppTheme.space32,
            AppTheme.space40,
          );

    return Center(
      child: Padding(
        padding: outerPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: frameSize,
              height: frameSize,
              decoration: BoxDecoration(
                color: isError ? colors.errorHighlight : colors.surfaceCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: isError
                    ? null
                    : Border.all(color: colors.surfaceBorder),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: isError ? colors.error : colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.space20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.space8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTheme.space20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact inline empty-state row: an icon plus a hint, for use inside a
/// list or panel that would otherwise just look blank when there's nothing
/// to show yet.
class EmptyStateHint extends StatelessWidget {
  const EmptyStateHint({
    super.key,
    required this.icon,
    required this.text,
    this.padding = const EdgeInsets.symmetric(
      vertical: AppTheme.space24,
      horizontal: AppTheme.space16,
    ),
  });

  final IconData icon;
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(icon, size: AppTheme.icon18, color: context.colors.textTertiary),
          const SizedBox(width: AppTheme.space10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

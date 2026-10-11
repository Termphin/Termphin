import 'package:flutter/material.dart';

import '../../theme/theme.dart';

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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: context.colors.surfaceCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: context.colors.surfaceBorder),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 26,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
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
    this.padding = const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
          Icon(icon, size: 18, color: context.colors.textTertiary),
          const SizedBox(width: 10),
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

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// How loud a badge is.
enum BadgeTone {
  /// Filled with the accent. For something worth the user's eye - a row that
  /// was not there last version.
  accent,

  /// Tinted, for a label that states a fact about the row it sits on rather
  /// than asking to be noticed.
  quiet,
}

/// The small pill beside a title: "New", "Default".
///
/// One widget because there were two hand-rolled copies of the same shape and
/// they had already drifted apart on colour. [BadgeTone.accent] fills with
/// `primary` and writes in `onPrimary`; tinting the fill with `primaryMuted`
/// and writing in `primary` - which is what the "New" pill used to do - puts
/// two shades of the accent on top of each other and reads as smudged.
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = BadgeTone.quiet});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      BadgeTone.accent => (colors.primary, colors.onPrimary),
      BadgeTone.quiet => (colors.primaryMuted, colors.primary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

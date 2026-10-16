import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// How loud a badge is, and what it reports.
enum BadgeTone {
  /// Filled with the accent. For something worth the user's eye - a row that
  /// was not there last version.
  accent,

  /// Tinted, for a label that states a fact about the row it sits on rather
  /// than asking to be noticed.
  quiet,

  /// The card's own fill behind a hairline, in secondary text: a count beside
  /// a section title, present without competing with it.
  neutral,

  /// The accent's faint highlight with accent text: a count on something
  /// active, such as running tunnels in a menu.
  highlight,

  /// A state that went well, tinted in the success colour.
  success,

  /// A state that needs a look, tinted in the warning colour.
  warning,

  /// A state that failed, tinted in the error colour.
  error,
}

/// The small pill beside a title: "New", "Default", a count, a status.
///
/// One widget because there were several hand-rolled copies of the same shape
/// and they had already drifted apart on colour and corner. [BadgeTone.accent]
/// fills with `primary` and writes in `onPrimary`; tinting the fill with
/// `primaryMuted` and writing in `primary` - which is what the "New" pill used
/// to do - puts two shades of the accent on top of each other and reads as
/// smudged.
class AppBadge extends StatelessWidget {
  const AppBadge(
    String this._text, {
    super.key,
    this.tone = BadgeTone.quiet,
    this.icon,
  }) : count = null;

  /// A number beside a title or menu entry, set a step larger than a word
  /// badge so the digits stay legible.
  const AppBadge.count(
    int this.count, {
    super.key,
    this.tone = BadgeTone.neutral,
  }) : _text = null,
       icon = null;

  final String? _text;

  /// Set when this is a [AppBadge.count].
  final int? count;

  String get label => _text ?? '$count';

  bool get _count => count != null;

  final BadgeTone tone;

  /// Drawn before the label in the same colour.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      BadgeTone.accent => (colors.primary, colors.onPrimary),
      BadgeTone.quiet => (colors.primaryMuted, colors.primary),
      BadgeTone.neutral => (colors.surfaceCard, colors.textSecondary),
      BadgeTone.highlight => (colors.primaryHighlight, colors.primary),
      BadgeTone.success => (colors.successHighlight, colors.success),
      BadgeTone.warning => (colors.warningHighlight, colors.warning),
      BadgeTone.error => (colors.errorHighlight, colors.error),
    };
    final text = Text(
      label,
      style: TextStyle(
        fontSize: _count ? AppTheme.font12 : AppTheme.font11,
        height: 1.2,
        color: foreground,
        fontWeight: _count ? FontWeight.w600 : FontWeight.w700,
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _count ? AppTheme.space8 : AppTheme.space6,
        vertical: AppTheme.space2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: tone == BadgeTone.neutral
            ? Border.all(color: colors.surfaceBorder)
            : null,
      ),
      child: icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppTheme.icon12, color: foreground),
                const SizedBox(width: AppTheme.space4),
                text,
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Small uppercase caption used above a grouped section of content, plus the
/// optional line of explanation that goes under it.
///
/// That line was written out by hand at every section that needed one, each
/// copy carrying its own font size and spacing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.hint, this.color, this.icon});

  final String text;
  final String? hint;

  /// Tints the caption (and [icon]) for a section whose kind is the point,
  /// such as a release-notes category; null keeps the quiet tertiary grey.
  final Color? color;

  /// Drawn before the caption in the same colour.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = context.colors.sectionLabel.copyWith(color: color);
    final label = Text(text.toUpperCase(), style: style);
    final caption = SizedBox(
      width: double.infinity,
      child: icon == null
          ? label
          : Row(
              children: [
                Icon(icon, size: AppTheme.icon14, color: style.color),
                const SizedBox(width: AppTheme.space6),
                Flexible(child: label),
              ],
            ),
    );
    if (hint == null) return caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        caption,
        const SizedBox(height: AppTheme.space4),
        Text(
          hint!,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
        ),
      ],
    );
  }
}

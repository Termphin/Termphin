import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Small uppercase caption used above a grouped section of content, plus the
/// optional line of explanation that goes under it.
///
/// That line was written out by hand at every section that needed one, each
/// copy carrying its own font size and spacing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final label = Text(text.toUpperCase(), style: context.colors.sectionLabel);
    final caption = SizedBox(width: double.infinity, child: label);
    if (hint == null) return caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        caption,
        const SizedBox(height: 4),
        Text(
          hint!,
          style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

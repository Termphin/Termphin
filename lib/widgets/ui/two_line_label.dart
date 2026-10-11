import 'package:flutter/material.dart';

/// A label that always reserves the height of two lines, whether the text
/// wraps to one or two - so a short label ("Paste") and a long one ("Manage
/// tunnels") don't leave their surrounding icon sitting at different
/// heights depending on how much text happened to wrap. Used by both the
/// command palette grid and its reorder list in Settings, so the two read
/// as the same set of tiles rather than two different layouts.
class TwoLineLabel extends StatelessWidget {
  const TwoLineLabel({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final lineHeight = (style.fontSize ?? 14) * (style.height ?? 1.3);
    return SizedBox(
      height: lineHeight * 2,
      child: Align(
        alignment: textAlign == TextAlign.center
            ? Alignment.topCenter
            : AlignmentDirectional.topStart,
        child: Text(
          text,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

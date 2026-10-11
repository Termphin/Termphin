import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Shared bordered surface used for grouped settings/content sections.
///
/// [clipChild] clips the child to a slightly tighter inner radius, which is
/// needed when the child is a Column of rows separated by full-bleed
/// dividers (e.g. [AppDivider]) so the divider doesn't overhang the corners.
/// That inner radius matches the border's own exactly - not some unrelated
/// smaller constant - so the clip stays seamless instead of visibly cutting
/// the corner short.
///
/// The content sits in a transparent `Material` so it paints nothing of its
/// own, but is still the nearest `Material` for whatever is inside: a
/// `ListTile` draws its ink splash on that, and without one the card's own
/// background would be the nearest thing under the tile and swallow the
/// splash, leaving every row in every card tapping with no feedback at
/// all.
///
/// The border itself is dark-mode only: dark separates a card from the
/// background by the step between their colours, and a stroke around every
/// card on top of that would turn a screen of them into a wireframe.
/// Light needs the stroke, since white on near-white has no step.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.clipChild = false});

  /// A card of stacked rows (e.g. form fields or list tiles) separated by
  /// full-bleed [AppDivider]s, clipped to the card's rounded corners.
  AppCard.fields({super.key, required List<Widget> children})
    : child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
      clipChild = true;

  final Widget child;
  final bool clipChild;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      type: MaterialType.transparency,
      child: clipChild
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd - 1),
              child: child,
            )
          : child,
    );
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: colors.isDark ? null : Border.all(color: colors.surfaceBorder),
      ),
      child: content,
    );
  }
}

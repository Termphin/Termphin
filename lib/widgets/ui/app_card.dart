import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'selection_action_bar.dart';

/// The one card in the app: grouped settings and content sections, and the
/// tappable cards lists and sheets are made of.
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
/// all. With [onTap] or [onLongPress] the whole card is one `InkWell` on that
/// same transparent `Material`, so the splash shows on top of the fill. The
/// fill and border animate, so selecting a card cross-fades rather than
/// snapping - except on an open segment, whose missing bottom edge has no
/// colour to tween and would break the uniform border a rounded box needs.
///
/// The border of a plain card is light-mode only: dark separates a card from
/// the background by the step between their colours, and a stroke around
/// every card on top of that would turn a screen of them into a wireframe.
/// Light needs the stroke, since white on near-white has no step. An
/// [elevated] card sits on another surface - a sheet, a panel - where that
/// step is too small to carry the edge, so it keeps its border in both
/// palettes. A [selected] card takes the app's one selection look,
/// [SelectionStyle]: a faint accent tint and an accent outline.
///
/// [AppCard.segment] is one piece of a stitched stack - a machine and the
/// sessions under it - drawn as a single card: only the first segment rounds
/// its top, only the last rounds its bottom and closes the bottom edge, so
/// neighbours share one hairline instead of drawing two.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.clipChild = false,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.elevated = false,
    this.padding,
    this.borderRadius,
  }) : _openBottom = false;

  /// One segment of a stitched stack; see the class docs.
  AppCard.segment({
    super.key,
    required this.child,
    required bool first,
    required bool last,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.elevated = true,
    this.padding,
  }) : clipChild = false,
       borderRadius = BorderRadius.vertical(
         top: first ? const Radius.circular(AppTheme.radiusMd) : Radius.zero,
         bottom: last ? const Radius.circular(AppTheme.radiusMd) : Radius.zero,
       ),
       _openBottom = !last;

  /// A card of stacked rows (e.g. form fields or list tiles) separated by
  /// full-bleed [AppDivider]s, clipped to the card's rounded corners.
  AppCard.fields({
    super.key,
    required List<Widget> children,
    this.elevated = false,
    this.borderRadius,
  }) : child = Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: children,
       ),
       clipChild = true,
       onTap = null,
       onLongPress = null,
       selected = false,
       padding = null,
       _openBottom = false;

  final Widget child;
  final bool clipChild;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool elevated;

  /// Space between the card's edge and [child].
  final EdgeInsetsGeometry? padding;

  /// Defaults to [AppTheme.radiusMd] on every corner; a card that is one
  /// segment of a stack passes only the corners it owns.
  final BorderRadius? borderRadius;

  final bool _openBottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = borderRadius ?? BorderRadius.circular(AppTheme.radiusMd);
    final base = elevated ? colors.surfaceElevated : colors.surfaceCard;
    final fill = SelectionStyle.fill(context, base, selected: selected);
    final bordered = selected || elevated || !colors.isDark;
    final side = SelectionStyle.side(context, selected: selected);
    final decoration = BoxDecoration(
      color: fill,
      borderRadius: radius,
      border: !bordered
          ? null
          : Border(
              top: side,
              left: side,
              right: side,
              bottom: _openBottom && !selected ? BorderSide.none : side,
            ),
    );

    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    if (clipChild) {
      content = ClipRRect(
        borderRadius: _inset(radius, AppTheme.hairline),
        child: content,
      );
    }

    final surface = Material(
      type: MaterialType.transparency,
      child: onTap == null && onLongPress == null
          ? content
          : InkWell(
              borderRadius: radius,
              onTap: onTap,
              onLongPress: onLongPress,
              child: content,
            ),
    );
    if (_openBottom) {
      return DecoratedBox(decoration: decoration, child: surface);
    }
    return AnimatedContainer(
      duration: AppTheme.interactiveDuration,
      curve: AppTheme.interactiveCurve,
      decoration: decoration,
      child: surface,
    );
  }

  static BorderRadius _inset(BorderRadius r, double by) {
    Radius shrink(Radius c) => Radius.elliptical(
      (c.x - by).clamp(0, double.infinity),
      (c.y - by).clamp(0, double.infinity),
    );
    return BorderRadius.only(
      topLeft: shrink(r.topLeft),
      topRight: shrink(r.topRight),
      bottomLeft: shrink(r.bottomLeft),
      bottomRight: shrink(r.bottomRight),
    );
  }
}

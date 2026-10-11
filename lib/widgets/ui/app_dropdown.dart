import 'dart:math' as math;

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// Callers build the entries, so they need these; nothing else about the
/// package should have to leak into a screen.
export 'package:dropdown_button2/dropdown_button2.dart'
    show DropdownDirection, DropdownItem;

/// Panel styling shared by every dropdown in the app.
///
/// The reveal is collapsed to nothing so the panel only fades in: the default
/// wipes itself open from the button's edge, which reads as the menu growing
/// out of whatever was tapped and lands differently depending on where on
/// screen that was. A plain opacity change looks the same everywhere - the
/// interval is not zero-width because the reveal divides by its own length.
/// The scrollbar's thumb is always visible, as the only sign there is more
/// to the menu below.
DropdownStyleData appDropdownStyle(
  BuildContext context, {
  double? width,
  double? maxHeight,
  DropdownDirection direction = DropdownDirection.textDirection,
  Offset offset = Offset.zero,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 6),
}) => DropdownStyleData(
  width: width,
  maxHeight: maxHeight,
  direction: direction,
  offset: offset,
  padding: padding,
  openInterval: const Interval(0, 0.001),
  decoration: BoxDecoration(
    color: context.colors.surfaceElevated,
    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
    border: Border.all(color: context.colors.surfaceBorderStrong),
  ),
  elevation: 0,
  scrollbarTheme: ScrollbarThemeData(
    thumbVisibility: const WidgetStatePropertyAll(true),
    thumbColor: WidgetStatePropertyAll(context.colors.textTertiary),
    thickness: const WidgetStatePropertyAll(3),
    radius: const Radius.circular(2),
    crossAxisMargin: 3,
  ),
);

MenuItemStyleData appDropdownItemStyle({
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12),
}) => MenuItemStyleData(
  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
  padding: padding,
);

/// A dropdown that fires actions rather than picking a value - the `⋮` menus.
///
/// Uses [DropdownButton2] like the value dropdowns in settings so both open
/// the same way, and hides the underline the package draws under every button
/// by default (a stray hairline under an icon-only button).
class AppActionDropdown<T> extends StatefulWidget {
  const AppActionDropdown({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = PhosphorIconsRegular.dotsThreeVertical,
    this.iconSize = 15,
    this.iconColor,
    this.buttonSize = 28,
    this.width = 252,
    this.direction = DropdownDirection.left,
    this.offset = const Offset(0, -6),
    this.tooltip,
    this.child,
    this.openDropdownListenable,
  });

  final List<DropdownItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final double buttonSize;
  final double width;
  final DropdownDirection direction;
  final Offset offset;
  final String? tooltip;

  /// Overrides the default `⋮` icon button as the trigger - the whole toolbar
  /// key tile, for instance, so tapping the tile itself opens the menu
  /// instead of needing a separate icon next to it.
  final Widget? child;

  /// Lets a caller open this exact menu without a tap on [child] - a file row
  /// that turns out to be binary opening its own actions menu when tapped
  /// directly, say, rather than only through its `⋮` button.
  final Listenable? openDropdownListenable;

  @override
  State<AppActionDropdown<T>> createState() => _AppActionDropdownState<T>();
}

/// How close a menu may come to the side of the screen. The package clamps
/// to the edge itself, which left a menu opened near it flush against the
/// glass.
const kMenuScreenMargin = 8.0;

/// The horizontal nudge that keeps a menu [width] wide, opened from
/// [button] towards [direction], [kMenuScreenMargin] clear of both sides of a
/// [screenWidth] wide screen. Zero when it already is, or cannot be.
@visibleForTesting
double menuEdgeNudge({
  required Rect button,
  required double width,
  required double screenWidth,
  required DropdownDirection direction,
  required double offsetX,
}) {
  final left = switch (direction) {
    DropdownDirection.left => button.right - width + offsetX,
    DropdownDirection.right ||
    DropdownDirection.textDirection => button.left + offsetX,
    DropdownDirection.center => button.center.dx - width / 2 + offsetX,
  };
  final max = screenWidth - width - kMenuScreenMargin;
  if (max < kMenuScreenMargin) return 0;
  return left.clamp(kMenuScreenMargin, max) - left;
}

/// Below this much room under its button a menu is not worth keeping there:
/// the package moves it up over the button instead.
const kMenuMinAnchoredHeight = 160.0;

/// How tall a menu opened under [button] may be and still end
/// [kMenuScreenMargin] above whatever covers the bottom of a [screenHeight]
/// tall screen - the system bar, or the keyboard ([bottomInset]). Anything
/// taller scrolls inside it. Null when there is too little room below.
@visibleForTesting
double? menuMaxHeight({
  required Rect button,
  required double screenHeight,
  required double bottomInset,
  required double offsetY,
}) {
  final top = button.bottom - offsetY;
  final room = screenHeight - bottomInset - kMenuScreenMargin - top;
  return room >= kMenuMinAnchoredHeight ? room : null;
}

class _AppActionDropdownState<T> extends State<AppActionDropdown<T>> {
  double _nudge = 0;
  double? _maxHeight;

  /// Measured after every layout, so a tap finds it ready, and again on the
  /// finger going down, since a strip scrolling moves the button without
  /// rebuilding it.
  void _fitToScreen() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final button = box.localToGlobal(Offset.zero) & box.size;
    final media = MediaQuery.of(context);
    final nudge = menuEdgeNudge(
      button: button,
      width: widget.width,
      screenWidth: media.size.width,
      direction: widget.direction,
      offsetX: widget.offset.dx,
    );
    final maxHeight = menuMaxHeight(
      button: button,
      screenHeight: media.size.height,
      bottomInset: math.max(media.viewPadding.bottom, media.viewInsets.bottom),
      offsetY: widget.offset.dy,
    );
    if (nudge != _nudge || maxHeight != _maxHeight) {
      setState(() {
        _nudge = nudge;
        _maxHeight = maxHeight;
      });
    }
  }

  /// The package pops its own menu route *after* `onChanged` returns, so an
  /// action that opens a dialog straight away would be the route that pop
  /// hits: the menu stays on the stack and the dialog dies with the wrong
  /// result type. Waiting a frame lets the menu close first.
  void _handleChanged(T? value) {
    if (value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelected(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToScreen());
    final tooltip = widget.tooltip;
    final button =
        widget.child ??
        SizedBox.square(
          dimension: widget.buttonSize,
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.iconColor ?? context.colors.textTertiary,
            ),
          ),
        );
    return Listener(
      onPointerDown: (_) => _fitToScreen(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton2<T>(
          customButton: tooltip == null
              ? button
              : Tooltip(message: tooltip, child: button),
          items: widget.items,
          onChanged: _handleChanged,
          openDropdownListenable: widget.openDropdownListenable,
          dropdownStyleData: appDropdownStyle(
            context,
            width: widget.width,
            maxHeight: _maxHeight,
            direction: widget.direction,
            offset: widget.offset + Offset(_nudge, 0),
          ),
          menuItemStyleData: appDropdownItemStyle(),
        ),
      ),
    );
  }
}

/// One row inside a dropdown panel, with or without a leading icon.
///
/// Every menu in the app builds its entries from this, so a row is the same
/// height whether it names an action or picks a value. Use it with
/// `DropdownItem(intrinsicHeight: true)`: the row sizes itself, and a fixed
/// `height` would only cut it off once the text grows - the breathing room
/// around an entry comes from its padding instead, which is also what makes
/// the row follow the font scale.
///
/// The selection tick carries the selection on its own; recolouring the
/// label as well would put the accent on a whole row of text and, next to
/// a group's own colour dot, leave two different blues arguing over the
/// same entry. The icon colour is a step quieter than the label by
/// default, so the words lead and the icons only mark the rows - unless
/// the entry is coloured, when both carry it.
class AppDropdownItem extends StatelessWidget {
  const AppDropdownItem({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.color,
    this.selected = false,
    this.fontFamily,
    this.trailing,
  });

  final String label;

  /// Stands where [icon] would, for an entry marked by something that is not
  /// an icon - a group's colour dot. Ignored when [icon] is given.
  final Widget? leading;

  /// Draws the label in the face it names, for the font picker.
  final String? fontFamily;

  /// Omitted by value pickers, where a column of icons would say nothing.
  final IconData? icon;

  /// Overrides the text and icon colour, for destructive entries.
  final Color? color;

  /// Marks the entry a value dropdown is currently showing.
  final bool selected;

  /// Sits at the row's far end - a count, say.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.onSurface;
    final iconColor = color ?? context.colors.textSecondary;
    final iconData = icon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (iconData != null) ...[
            Icon(iconData, size: 18, color: iconColor),
            const SizedBox(width: 12),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: effective,
                fontFamily: fontFamily,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          ?trailing,
          if (selected) ...[
            const SizedBox(width: 10),
            Icon(
              PhosphorIconsRegular.check,
              size: 14,
              color: context.colors.primary,
            ),
          ],
        ],
      ),
    );
  }
}

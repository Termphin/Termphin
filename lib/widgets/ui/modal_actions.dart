import 'package:flutter/material.dart';

import '../../utils/platform_info.dart';

/// How [ModalActions] lays two buttons out on a phone.
enum ModalActionsLayout {
  /// One above the other, each the full width.
  stacked,

  /// Side by side, sharing the width.
  sideBySide,
}

/// The buttons a sheet, a form or a dialog ends in.
///
/// On a phone they run edge to edge, where a thumb finds them. On a desktop
/// that same button is a bar across a 600 px dialog with a few words lost in
/// its middle: there the buttons keep their own width and stand at the
/// right, the secondary one before the primary, as in every dialog on the
/// system. Screens hand their buttons here rather than choosing a width.
class ModalActions extends StatelessWidget {
  const ModalActions({
    super.key,
    required this.primary,
    this.secondary,
    this.layout = ModalActionsLayout.stacked,
    this.secondaryFirst = false,
    this.gap = 10,
    this.phoneHeight,
  });

  final Widget primary;
  final Widget? secondary;
  final ModalActionsLayout layout;

  /// Stacked on a phone, whether [secondary] goes above [primary].
  final bool secondaryFirst;

  /// The space between the two on a phone.
  final double gap;

  /// A fixed height for [primary] on a phone, where one is wanted.
  final double? phoneHeight;

  /// Narrowest a desktop button is drawn, so "OK" is still a target.
  static const double _desktopMinWidth = 96;

  @override
  Widget build(BuildContext context) {
    final secondary = this.secondary;
    if (isDesktopPlatform) {
      Widget sized(Widget button) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _desktopMinWidth),
        child: button,
      );
      return Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [if (secondary != null) sized(secondary), sized(primary)],
        ),
      );
    }
    final main = phoneHeight == null
        ? primary
        : SizedBox(height: phoneHeight, child: primary);
    if (layout == ModalActionsLayout.sideBySide && secondary != null) {
      return Row(
        children: [
          Expanded(child: secondary),
          SizedBox(width: gap),
          Expanded(child: main),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (secondary != null && secondaryFirst) ...[
          secondary,
          SizedBox(height: gap),
        ],
        main,
        if (secondary != null && !secondaryFirst) ...[
          SizedBox(height: gap),
          secondary,
        ],
      ],
    );
  }
}

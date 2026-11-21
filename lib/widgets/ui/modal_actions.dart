import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';
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
/// On a phone they run edge to edge, where a thumb finds them; on anything
/// wider, a tablet or a phone on its side, they stop at
/// [AppTheme.buttonMaxWidth], centred (see [ButtonWidth]). On a desktop
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
      return ButtonWidth(
        child: Row(
          children: [
            Expanded(child: secondary),
            SizedBox(width: gap),
            Expanded(child: main),
          ],
        ),
      );
    }
    return ButtonWidth(
      child: Column(
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
      ),
    );
  }
}

/// A button, or a column of them, that runs the full width on a phone and
/// stops at [AppTheme.buttonMaxWidth] on anything wider - a tablet, a phone
/// on its side - placed by [alignment], so it does not stretch into a bar.
class ButtonWidth extends StatelessWidget {
  const ButtonWidth({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < kWideLayoutMinWidth) return child;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTheme.buttonMaxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

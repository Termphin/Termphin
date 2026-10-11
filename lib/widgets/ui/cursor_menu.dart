import 'package:flutter/material.dart';

/// A small floating menu anchored to a point in the enclosing Stack - built
/// for the "paste path after upload" menu, but generic on [child] so any
/// future menu that needs to sit at the terminal cursor (or any other point)
/// reuses this instead of hand-rolling positioning again.
///
/// Tapping anywhere outside [child] calls [onDismiss]; the caller owns
/// removing the menu from the tree when that fires, and any other dismiss
/// trigger (e.g. the user starting to type).
class CursorMenu extends StatelessWidget {
  const CursorMenu({
    super.key,
    required this.anchor,
    required this.onDismiss,
    required this.child,
  });

  /// Where the menu points to, in the coordinate space of the enclosing
  /// Stack.
  final Offset anchor;
  final VoidCallback onDismiss;
  final Widget child;

  /// Assumed footprint of [child], since positioning happens before it is
  /// measured. Only keeps the menu from spilling off the edge - the menu
  /// itself sizes to its own content.
  static const _assumedWidth = 240.0;
  static const _assumedHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxLeft = (constraints.maxWidth - _assumedWidth).clamp(
            8.0,
            double.infinity,
          );
          final maxTop = (constraints.maxHeight - _assumedHeight).clamp(
            8.0,
            double.infinity,
          );
          final left = anchor.dx.clamp(8.0, maxLeft);
          final top = anchor.dy.clamp(8.0, maxTop);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onDismiss,
                ),
              ),
              Positioned(left: left, top: top, child: child),
            ],
          );
        },
      ),
    );
  }
}

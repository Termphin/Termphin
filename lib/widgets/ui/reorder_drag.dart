import 'package:flutter/material.dart';

import '../../utils/platform_info.dart';

/// Starts a [ReorderableListView] drag from anywhere on [child]: straight
/// away with a pointer on a desktop, where pressing and holding to move
/// something reads as broken, and after a hold on a phone, where a plain drag
/// is the list scrolling. A click or tap still reaches [child] either way - a
/// drag only starts past the slop.
class ReorderDragListener extends StatelessWidget {
  const ReorderDragListener({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => isDesktopPlatform
      ? ReorderableDragStartListener(index: index, child: child)
      : ReorderableDelayedDragStartListener(index: index, child: child);
}

/// A [Draggable] on a desktop and a [LongPressDraggable] on a phone, for the
/// same reason as [ReorderDragListener].
Widget platformDraggable<T extends Object>({
  Key? key,
  required T data,
  required Widget feedback,
  required Widget child,
  Widget? childWhenDragging,
  Axis? axis,
  VoidCallback? onDragStarted,
}) => isDesktopPlatform
    ? Draggable<T>(
        key: key,
        data: data,
        axis: axis,
        onDragStarted: onDragStarted,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: child,
      )
    : LongPressDraggable<T>(
        key: key,
        data: data,
        axis: axis,
        onDragStarted: onDragStarted,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: child,
      );

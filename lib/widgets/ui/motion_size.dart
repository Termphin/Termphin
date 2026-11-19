import 'package:flutter/widgets.dart';

/// [AnimatedSize], unless [duration] is zero - a desktop's, where every
/// motion is - and then just [child].
///
/// An [AnimatedSize] given no time still runs its controller, and finishing
/// it re-dirties the layout it is in the middle of, which Flutter asserts
/// against. With nothing to animate there is nothing to wrap.
class MotionSize extends StatelessWidget {
  const MotionSize({
    super.key,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}

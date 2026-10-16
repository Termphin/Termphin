import 'package:flutter/widgets.dart';

/// Shows [child] at [opacity] over a solid [color], by painting that colour
/// over it rather than by fading the child itself.
///
/// An opacity between 0 and 1 renders the whole child offscreen and blends it
/// back every frame, which for a full screen - a terminal, a list of machines -
/// is the most expensive thing a transition can do. When what lies behind is a
/// plain colour, laying that colour over the child at the inverse strength
/// looks exactly the same and costs one rectangle. At 0 the child is not
/// painted at all, at 1 it is painted untouched.
///
/// Only right for a fade-through - one screen gone before the next appears -
/// where the child is never meant to show anything but [color] through it.
class FadeOverColor extends StatelessWidget {
  const FadeOverColor({
    super.key,
    required this.opacity,
    required this.color,
    required this.child,
  });

  final double opacity;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cover = (1 - opacity).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity <= 0 ? 0 : 1,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: color.withValues(alpha: color.a * cover),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [FadeOverColor] driven by an animation, rebuilding only itself each frame;
/// [child] is built once and passed through.
class FadeOverColorTransition extends StatelessWidget {
  const FadeOverColorTransition({
    super.key,
    required this.opacity,
    required this.color,
    required this.child,
  });

  final Animation<double> opacity;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: opacity,
    builder: (context, child) =>
        FadeOverColor(opacity: opacity.value, color: color, child: child!),
    child: child,
  );
}

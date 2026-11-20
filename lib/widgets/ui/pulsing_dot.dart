import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// A filled dot that breathes - fading and shrinking a little and back -
/// for something in progress. With animations turned off in the system it
/// stays still, filled.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTheme.motionPulse,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Icon(
      PhosphorIconsFill.circle,
      size: widget.size,
      color: widget.color,
    );
    if (MediaQuery.disableAnimationsOf(context)) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(_curve),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.75).animate(_curve),
        child: dot,
      ),
    );
  }
}

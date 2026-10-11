import 'package:flutter/widgets.dart';

/// Two-finger pinch that reports a font size, for a child that scrolls.
///
/// Raw pointers rather than a scale gesture: a scale recogniser takes part in
/// the gesture arena and wins one-finger drags as well, which stops the text
/// under it from scrolling. A [Listener] only watches, so the child keeps
/// every gesture it had.
class PinchFontZoom extends StatefulWidget {
  const PinchFontZoom({
    super.key,
    required this.fontSize,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.child,
  });

  final double fontSize;
  final double min;
  final double max;

  /// Called as the pinch moves, with the size rounded to half a point.
  final ValueChanged<double> onChanged;
  final Widget child;

  @override
  State<PinchFontZoom> createState() => _PinchFontZoomState();
}

class _PinchFontZoomState extends State<PinchFontZoom> {
  final _pointers = <int, Offset>{};
  double? _startDistance;
  double _startSize = 0;
  double? _last;

  double get _distance {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _startDistance = _distance;
      _startSize = widget.fontSize;
      _last = null;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final start = _startDistance;
    if (_pointers.length != 2 || start == null || start <= 0) return;
    final raw = (_startSize * _distance / start).clamp(widget.min, widget.max);
    final size = (raw * 2).round() / 2;
    if (size == _last) return;
    _last = size;
    widget.onChanged(size);
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _startDistance = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

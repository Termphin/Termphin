import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/settings/floating_dock_settings.dart';
import '../../theme/theme.dart';

/// How far the special-keys toolbar has risen above its resting position to
/// clear the keyboard (see the `Positioned` around it in `TerminalScreen` -
/// `bottom: 6 + max(viewPadding.bottom, inset)`, which only grows once the
/// raw inset passes the safe-area gap the toolbar already rests above).
/// Using the raw inset directly instead double-counts that resting gap as
/// extra empty space. Shared with anything else that has to sit flush above
/// the toolbar, like the upload progress bar.
double toolbarLiftFor(BuildContext context) {
  final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
  final rawInset = MediaQuery.viewInsetsOf(context).bottom;
  return rawInset > viewPaddingBottom ? rawInset - viewPaddingBottom : 0.0;
}

/// A round button that floats over the terminal, independent of the
/// customizable special-keys toolbar. Drag it and on release it snaps
/// horizontally to whichever side it's nearest to, but keeps wherever it was
/// dragged to vertically - anywhere along the left or right edge, not just
/// the four corners. Tap invokes [onTap] - what that opens is the caller's
/// business, not this widget's.
class FloatingActionDock extends StatefulWidget {
  const FloatingActionDock({super.key, required this.onTap, this.buttonKey});

  final VoidCallback onTap;

  /// Lets a caller find the button's on-screen rect (`buttonKey.currentContext
  /// ?.findRenderObject()`) to anchor a menu to wherever it's currently
  /// docked or was last dragged to.
  final GlobalKey? buttonKey;

  @override
  State<FloatingActionDock> createState() => _FloatingActionDockState();
}

/// Self-contained on purpose: a caller only has to drop this in as a plain
/// `Stack` child. The `Positioned`/`AnimatedPositioned` this needs for the
/// drag are only valid as direct children of a `Stack`, so that `Stack`
/// lives in here rather than being a constraint on however the caller is
/// laid out.
class _FloatingActionDockState extends State<FloatingActionDock> {
  static const _buttonSize = 44.0;
  static const _margin = 12.0;

  late FloatingDockSide _side;
  late double _verticalFraction;

  /// Live top-left position while a drag is in progress, in the
  /// [LayoutBuilder] area's own coordinates. Null when docked, so the button
  /// renders at [_dockedPosition] instead.
  Offset? _dragPosition;

  @override
  void initState() {
    super.initState();
    _side = floatingDockSettings.side.value;
    _verticalFraction = floatingDockSettings.verticalFraction.value;
  }

  /// This Stack's own height stays fixed while the keyboard opens - the
  /// terminal pans natively instead of Flutter resizing it - so the
  /// fraction has to be measured against the height actually free of the
  /// risen toolbar, or "50%" would sit half-hidden behind it.
  double _visibleHeight(Size area, BuildContext context) {
    final visible = area.height - toolbarLiftFor(context);
    return visible < _buttonSize + 2 * _margin ? area.height : visible;
  }

  Offset _dockedPosition(Size area, double visibleHeight) {
    final x = switch (_side) {
      FloatingDockSide.left => _margin,
      FloatingDockSide.right => area.width - _buttonSize - _margin,
    };
    final maxY = math.max(_margin, visibleHeight - _buttonSize - _margin);
    final y = (_verticalFraction * visibleHeight).clamp(_margin, maxY);
    return Offset(x, y);
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    Size area,
    double visibleHeight,
  ) {
    final current = _dragPosition ?? _dockedPosition(area, visibleHeight);
    final next = current + details.delta;
    setState(() {
      _dragPosition = Offset(
        next.dx.clamp(0.0, area.width - _buttonSize),
        next.dy.clamp(0.0, visibleHeight - _buttonSize),
      );
    });
  }

  void _onPanEnd(Size area, double visibleHeight) {
    final pos = _dragPosition;
    if (pos == null) return;
    final centerX = pos.dx + _buttonSize / 2;
    final side = centerX < area.width / 2
        ? FloatingDockSide.left
        : FloatingDockSide.right;
    final fraction = ((pos.dy + _buttonSize / 2) / visibleHeight).clamp(
      0.0,
      1.0,
    );
    HapticFeedback.selectionClick();
    setState(() {
      _side = side;
      _verticalFraction = fraction;
      _dragPosition = null;
    });
    unawaited(floatingDockSettings.side.set(side));
    unawaited(floatingDockSettings.verticalFraction.set(fraction));
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final visibleHeight = _visibleHeight(area, context);
          final dragging = _dragPosition != null;
          final position =
              _dragPosition ?? _dockedPosition(area, visibleHeight);
          return Stack(
            children: [
              AnimatedPositioned(
                duration: dragging ? Duration.zero : AppTheme.motionFast,
                curve: Curves.easeOutCubic,
                left: position.dx,
                top: position.dy,
                child: GestureDetector(
                  key: widget.buttonKey,
                  onPanUpdate: (d) => _onPanUpdate(d, area, visibleHeight),
                  onPanEnd: (_) => _onPanEnd(area, visibleHeight),
                  onTap: _handleTap,
                  child: const _DockButton(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton();

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).dividerColor;
    return Container(
      width: _FloatingActionDockState._buttonSize,
      height: _FloatingActionDockState._buttonSize,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: AppTheme.raisedShadow,
      ),
      child: Icon(
        PhosphorIconsRegular.list,
        size: AppTheme.icon20,
        color: context.colors.primary,
      ),
    );
  }
}

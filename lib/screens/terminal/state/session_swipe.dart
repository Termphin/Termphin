import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';

/// The horizontal drag that moves between tabs.
///
/// Lifted out of `TerminalScreenState`, which was holding eleven fields for
/// this one gesture alongside the tab strip's own state and the keyboard
/// measurement - three unrelated machines whose fields all read as "the
/// screen's state". Here the gesture owns its own, and the screen keeps only
/// [offset] and [targetIndex] to build with.
///
/// It does not know what a tab is: the screen supplies how many there are and
/// which is active, and hears back through [onCommit] when the gesture has
/// settled on a different one.
class SessionSwipeController extends ChangeNotifier {
  SessionSwipeController({
    required TickerProvider vsync,
    required this.tabCount,
    required this.activeIndex,
    required this.onCommit,
    required this.isBlocked,
  }) : _animation = AnimationController(
         vsync: vsync,
         duration: AppTheme.motionSlow,
       ) {
    _animation.addListener(() {
      final tween = _tween;
      if (tween != null) offset.value = tween.value;
    });
  }

  /// Below this the drag is a tap or a scroll, not a swipe.
  static const double _lockDistance = 12;

  /// How much more horizontal than vertical the drag has to be to count.
  static const double _horizontalBias = 1.25;

  /// Past either of these the gesture commits on release - a long enough
  /// drag, or a fast enough flick.
  static const double _maxCommitDistance = 96;
  static const double _commitFraction = 0.22;
  static const double _commitVelocity = 0.55;

  /// How far a tab that has nowhere to go is allowed to follow the finger.
  /// Enough to show the edge is real, not enough to look like a move.
  static const double _rubberBand = 0.18;

  /// Live drag distance, in pixels. A [ValueNotifier] rather than part of
  /// this notifier's own state: it changes on every pointer move, and the
  /// page that follows it must not take the whole screen's build with it.
  final ValueNotifier<double> offset = ValueNotifier(0);

  /// How many tabs there are, and which one is showing. Read through
  /// callbacks rather than stored, since the screen changes both underneath.
  final int Function() tabCount;
  final int Function() activeIndex;

  /// Called once the gesture has settled on [index]. The screen makes it
  /// active; this only decides when.
  final void Function(int index) onCommit;

  /// True while something else owns the pointer - a selection handle being
  /// dragged in the terminal, which a tab swipe must not steal.
  final bool Function() isBlocked;

  final AnimationController _animation;
  Animation<double>? _tween;

  int? _pointer;
  Offset? _start;
  Offset? _last;
  Duration? _startedAt;
  bool _locked = false;
  int? _targetIndex;
  int? _commitIndex;
  double _viewportWidth = 0;

  /// The tab the drag is heading towards, or null when it is heading off the
  /// end. The screen paints this one alongside the active tab.
  int? get targetIndex => _targetIndex;

  bool get isAnimating => _animation.isAnimating;

  /// The width one tab occupies, which the drag is measured against. Set from
  /// the screen's `LayoutBuilder`.
  set viewportWidth(double value) => _viewportWidth = value;

  void onPointerDown(PointerDownEvent event) {
    if (isBlocked()) return;
    if (tabCount() < 2 || _animation.isAnimating) return;
    if (_pointer != null) {
      cancel();
      return;
    }
    _pointer = event.pointer;
    _start = event.position;
    _last = event.position;
    _startedAt = event.timeStamp;
    _locked = false;
  }

  /// Checked again on every move, not just on the initial touch down: a
  /// selection handle can also be grabbed after the swipe has armed, since
  /// the long-press that creates a selection puts one right under the
  /// finger.
  void onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _start == null) return;
    if (isBlocked()) {
      cancel();
      return;
    }
    _last = event.position;
    final delta = event.position - _start!;

    if (!_locked) {
      if (delta.dx.abs() < _lockDistance) return;
      if (delta.dx.abs() <= delta.dy.abs() * _horizontalBias) {
        _reset();
        return;
      }
      _locked = true;
    }

    final target = activeIndex() + (delta.dx < 0 ? 1 : -1);
    final validTarget = target >= 0 && target < tabCount() ? target : null;
    if (_targetIndex != validTarget) {
      _targetIndex = validTarget;
      notifyListeners();
    }

    if (_viewportWidth <= 0) return;
    offset.value = validTarget == null
        ? delta.dx * _rubberBand
        : delta.dx.clamp(-_viewportWidth, _viewportWidth);
  }

  void onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    final end = _last ?? event.position;
    final startedAt = _startedAt;
    final wasLocked = _locked;
    _reset();
    if (start == null || startedAt == null || !wasLocked) {
      offset.value = 0;
      return;
    }

    final delta = end - start;
    final elapsedMs = math.max(1, (event.timeStamp - startedAt).inMilliseconds);
    final velocity = delta.dx / elapsedMs;
    final threshold = math.min(
      _maxCommitDistance,
      _viewportWidth * _commitFraction,
    );
    final commit =
        _targetIndex != null &&
        (offset.value.abs() >= threshold || velocity.abs() >= _commitVelocity);

    _animateTo(
      commit ? (delta.dx < 0 ? -_viewportWidth : _viewportWidth) : 0,
      commitIndex: commit ? _targetIndex : null,
    );
  }

  void cancel() {
    _reset();
    _animateTo(0);
  }

  void _animateTo(double target, {int? commitIndex}) {
    _commitIndex = commitIndex;
    _tween = Tween<double>(
      begin: offset.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic));
    _animation.forward(from: 0).whenComplete(() {
      final committed = _commitIndex;
      final changed = committed != null && committed != activeIndex();
      _targetIndex = null;
      offset.value = 0;
      _tween = null;
      _commitIndex = null;
      notifyListeners();

      if (committed == null) return;
      if (changed) HapticFeedback.selectionClick();
      onCommit(committed);
    });
  }

  void _reset() {
    _pointer = null;
    _start = null;
    _last = null;
    _startedAt = null;
    _locked = false;
  }

  @override
  void dispose() {
    _animation.dispose();
    offset.dispose();
    super.dispose();
  }
}

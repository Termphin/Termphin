import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import '../../utils/platform_info.dart';

/// Lets the arrow keys walk a screen's rows on a desktop: Down and Up move
/// the focus highlight from row to row, Home and End jump to the ends, and
/// Enter opens the one it is on, since a focused `InkWell` already answers
/// it.
///
/// A list has to be reachable without a mouse there, and Flutter's own
/// directional traversal is not that: it needs something focused to start
/// from, and from a row it will as happily land on the row's `⋮` button or
/// in the sidebar. This takes the keys while the focus is anywhere in
/// [child], and picks the next row by geometry - the nearest focusable
/// entirely below (or above) the current one, the widest where several
/// start on the same line, which is the row rather than a button inside it.
///
/// It holds the focus itself when nothing in [child] does, so the first
/// arrow has somewhere to be heard: when the screen appears, when its
/// section is switched back to (the shell turns `TickerMode` on for the
/// section on screen), and after a click anywhere in it - a frame after,
/// because the screens that drop the focus on a tap of empty space do it on
/// the same pointer-up, and would leave the arrows with nobody listening. A
/// text field keeps its own arrow keys - it handles them before they bubble
/// up to here.
///
/// A phone gets [child] untouched.
class ListKeyNavigation extends StatefulWidget {
  const ListKeyNavigation({super.key, required this.child});

  final Widget child;

  @override
  State<ListKeyNavigation> createState() => _ListKeyNavigationState();
}

class _ListKeyNavigationState extends State<ListKeyNavigation> {
  final _node = FocusNode(debugLabel: 'ListKeyNavigation', skipTraversal: true);
  bool _onScreen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!isDesktopPlatform) return;
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (onScreen && !_onScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimFocus());
    }
    _onScreen = onScreen;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Takes the focus for the list unless something of its own already has
  /// it, or a dialog is over the screen.
  void _claimFocus() {
    if (!mounted || _node.hasFocus) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _node.requestFocus();
  }

  List<FocusNode> _rows() => [
    for (final node in _node.traversalDescendants)
      if (node is! FocusScopeNode && node.context != null) node,
  ];

  /// The row to move to from [current]: the nearest one wholly past it in
  /// the direction asked for, or the first or last when nothing is focused
  /// yet.
  FocusNode? _neighbour(FocusNode? current, {required bool down}) {
    final rows = _rows();
    if (rows.isEmpty) return null;
    Iterable<FocusNode> candidates = rows;
    if (current != null) {
      final from = current.rect;
      candidates = rows.where(
        (node) => down
            ? node.rect.top >= from.bottom - 0.5
            : node.rect.bottom <= from.top + 0.5,
      );
    }
    return _edgeMost(candidates, first: down);
  }

  /// The topmost (or bottommost) of [nodes], the widest of those sharing
  /// that line.
  FocusNode? _edgeMost(Iterable<FocusNode> nodes, {required bool first}) {
    FocusNode? best;
    for (final node in nodes) {
      if (best == null) {
        best = node;
        continue;
      }
      final a = node.rect;
      final b = best.rect;
      final edge = first ? a.top - b.top : b.bottom - a.bottom;
      if (edge < -0.5 || (edge.abs() <= 0.5 && a.width > b.width)) best = node;
    }
    return best;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final focused = FocusManager.instance.primaryFocus;
    final current = focused == null || focused == _node ? null : focused;
    final FocusNode? target;
    if (key == LogicalKeyboardKey.arrowDown) {
      target = _neighbour(current, down: true);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      target = _neighbour(current, down: false);
    } else if (key == LogicalKeyboardKey.home) {
      target = _edgeMost(_rows(), first: true);
    } else if (key == LogicalKeyboardKey.end) {
      target = _edgeMost(_rows(), first: false);
    } else {
      return KeyEventResult.ignored;
    }
    if (target == null) return KeyEventResult.handled;
    final up = current != null && target.rect.top < current.rect.top;
    target.requestFocus();
    unawaited(
      Scrollable.ensureVisible(
        target.context!,
        duration: AppTheme.motionFast,
        alignmentPolicy: up
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return widget.child;
    return Listener(
      onPointerUp: (_) {
        WidgetsBinding.instance
          ..addPostFrameCallback((_) => _claimFocus())
          ..ensureVisualUpdate();
      },
      child: Focus(
        focusNode: _node,
        autofocus: true,
        onKeyEvent: _onKey,
        child: widget.child,
      ),
    );
  }
}

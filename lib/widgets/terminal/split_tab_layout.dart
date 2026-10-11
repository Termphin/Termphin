import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ssh_profile.dart';
import '../../theme/theme.dart';
import 'split_pane_chrome.dart';

/// Two sessions on one page, each under a bar naming it: stacked in
/// portrait, side by side in landscape. Orientation rather than the page's
/// own shape, which the keyboard changes - opening it must not flip the
/// split.
class SplitTabLayout extends StatefulWidget {
  const SplitTabLayout({
    super.key,
    required this.entry,
    required this.paneBuilder,
    required this.ratioOfFirst,
    required this.focusedId,
    required this.profileFor,
    required this.labelFor,
    required this.onFocusPane,
    required this.onSwap,
    required this.onRatioChanged,
    required this.onDividerHeldChanged,
  });

  /// The split's two sessions, in strip order.
  final List<String> entry;

  /// The actual content of a pane - a `SessionView`, typically.
  final Widget Function(String sessionId) paneBuilder;

  /// Share of the split the first session (`entry.first`) gets.
  final double ratioOfFirst;

  /// The session currently focused across the whole strip, not just this
  /// split.
  final String focusedId;

  final SshProfile Function(String sessionId) profileFor;
  final String Function(String sessionId) labelFor;

  /// A pane, or its header, was tapped into focus. [keyboardUp] asks the
  /// caller to chase the keyboard there once it is focused.
  final void Function(String sessionId, {bool keyboardUp}) onFocusPane;

  /// The other pane's header was dropped onto [sessionId]: trade places.
  final ValueChanged<String> onSwap;

  /// The divider moved: the new share of the split `entry.first` gets.
  final ValueChanged<double> onRatioChanged;

  /// The divider is being dragged, or was just let go.
  final ValueChanged<bool> onDividerHeldChanged;

  @override
  State<SplitTabLayout> createState() => _SplitTabLayoutState();
}

class _SplitTabLayoutState extends State<SplitTabLayout> {
  /// Each stacked pane's height with the keyboard down. A pane the keyboard
  /// hides keeps it, so its shell is not told the window shrank.
  final Map<String, double> _paneExtents = {};

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.orientationOf(context) == Orientation.portrait) {
      return _buildStackedSplit();
    }
    final first = widget.entry.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(
          0.0,
          constraints.maxWidth - kSplitDividerThickness,
        );
        final firstExtent = available * widget.ratioOfFirst;
        Widget column(String id, double width) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              id,
              keyboardUp: false,
              width: width,
              axis: Axis.horizontal,
            ),
            Expanded(child: _buildPane(id)),
          ],
        );
        return Row(
          key: ValueKey('splitView-$first'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: firstExtent, child: column(first, firstExtent)),
            _buildDivider(Axis.horizontal, available),
            Expanded(child: column(widget.entry.last, available - firstExtent)),
          ],
        );
      },
    );
  }

  /// One pane over the other, each under a bar naming it. With the keyboard
  /// up there is no room for two, so only the focused pane stays open and
  /// the other folds to its bar - a tap on that swaps them. The fold runs
  /// alongside the keyboard's own animation, so neither pane jumps at its
  /// start or its end.
  ///
  /// Whether the keyboard is up is read off the view, not the `MediaQuery`:
  /// the Scaffold has already taken the keyboard out of the body's, and
  /// resizes it instead. The pane folding away shrinks to nothing and the
  /// focused one takes whatever that leaves; a folding pane keeps the
  /// height it had and is clipped rather than squeezed, so its shell is
  /// never told the window shrank.
  Widget _buildStackedSplit() {
    final entry = widget.entry;
    final first = entry.first;
    final focused = widget.focusedId;
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardUp = View.of(context).viewInsets.bottom > 0;
        final folding = keyboardUp && entry.contains(focused);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: folding ? 1 : 0),
          duration: kSplitFoldDuration,
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final open = math.max(
              0.0,
              constraints.maxHeight -
                  kSplitDividerThickness -
                  kSplitHeaderHeight * 2,
            );
            final firstOpen = open * widget.ratioOfFirst;
            if (t == 0 && !keyboardUp) {
              _paneExtents[first] = firstOpen;
              _paneExtents[entry.last] = open - firstOpen;
            }
            final divider = kSplitDividerThickness * (1 - t);
            final room = math.max(
              0.0,
              constraints.maxHeight - divider - kSplitHeaderHeight * 2,
            );
            final foldedId = entry.contains(focused)
                ? entry.firstWhere((id) => id != focused)
                : null;
            double openOf(String id) =>
                id == first ? firstOpen : open - firstOpen;
            final foldedHeight = foldedId == null
                ? 0.0
                : openOf(foldedId) * (1 - t);
            double shown(String id) {
              if (foldedId == null) return openOf(id);
              return id == foldedId ? foldedHeight : room - foldedHeight;
            }

            Widget slot(String id) {
              final height = math.max(0.0, shown(id));
              final laidOut = id == foldedId && t > 0
                  ? (_paneExtents[id] ?? height)
                  : height;
              return SizedBox(
                key: ValueKey('splitPaneSlot-$id'),
                height: height,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: laidOut,
                    maxHeight: laidOut,
                    child: _buildPane(id),
                  ),
                ),
              );
            }

            return Column(
              key: ValueKey('splitView-$first'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(
                  first,
                  keyboardUp: keyboardUp,
                  width: constraints.maxWidth,
                ),
                slot(first),
                SizedBox(
                  height: divider,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: kSplitDividerThickness,
                      maxHeight: kSplitDividerThickness,
                      child: _buildDivider(Axis.vertical, open),
                    ),
                  ),
                ),
                _buildHeader(
                  entry.last,
                  keyboardUp: keyboardUp,
                  width: constraints.maxWidth,
                ),
                slot(entry.last),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDivider(Axis axis, double available) {
    return SplitDivider(
      axis: axis,
      onHeld: widget.onDividerHeldChanged,
      onDrag: (delta) {
        if (available <= 0) return;
        widget.onRatioChanged(
          (available * widget.ratioOfFirst + delta) / available,
        );
      },
    );
  }

  /// A pane's name bar. Held, it lifts like a tab does and is dragged onto
  /// the other pane to trade places with it.
  Widget _buildHeader(
    String sessionId, {
    required bool keyboardUp,
    required double width,
    Axis axis = Axis.vertical,
  }) {
    final focused = widget.focusedId == sessionId;
    SplitPaneHeader header({bool highlighted = false}) => SplitPaneHeader(
      profile: widget.profileFor(sessionId),
      label: widget.labelFor(sessionId),
      focused: focused || highlighted,
      onTap: () => widget.onFocusPane(sessionId, keyboardUp: keyboardUp),
    );
    return _buildSwapTarget(
      sessionId,
      (hovered) => LongPressDraggable<String>(
        key: ValueKey('splitHeader-$sessionId'),
        data: sessionId,
        axis: axis,
        onDragStarted: HapticFeedback.selectionClick,
        feedback: Theme(
          data: Theme.of(context),
          child: SizedBox(
            width: width,
            child: tabDragProxyDecorator(
              header(),
              0,
              const AlwaysStoppedAnimation(1),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: header()),
        child: header(highlighted: hovered),
      ),
    );
  }

  /// Takes the other pane's name bar when it is dropped here.
  Widget _buildSwapTarget(String sessionId, Widget Function(bool) builder) {
    final partner = widget.entry.firstWhere((id) => id != sessionId);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => partner == details.data,
      onAcceptWithDetails: (details) {
        HapticFeedback.mediumImpact();
        widget.onSwap(sessionId);
      },
      builder: (context, candidates, _) => builder(candidates.isNotEmpty),
    );
  }

  /// A touch anywhere in a pane focuses it, so the key toolbar and the dock
  /// act on the pane being looked at.
  Widget _buildPane(String sessionId) {
    final focused = widget.focusedId == sessionId;
    final accent = context.colors.primary;
    return _buildSwapTarget(
      sessionId,
      (hovered) => Listener(
        key: ValueKey('splitPane-$sessionId'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!focused) widget.onFocusPane(sessionId);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.paneBuilder(sessionId),
            IgnorePointer(
              child: AnimatedContainer(
                duration: AppTheme.motionFast,
                decoration: BoxDecoration(
                  color: hovered
                      ? accent.withValues(alpha: 0.12)
                      : accent.invisible,
                  border: Border.all(
                    color: hovered
                        ? accent.withValues(alpha: 0.6)
                        : accent.invisible,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

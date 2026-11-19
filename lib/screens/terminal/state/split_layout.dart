import 'dart:math' as math;
import 'dart:ui';

/// Which way a split runs: [sideBySide] puts its two halves left and right,
/// [stacked] one over the other.
enum SplitAxis { sideBySide, stacked }

/// Where focus or a pane goes from the one it is in.
enum SplitDirection { left, right, up, down }

/// A node of a split tree: one session, or two halves of the space.
sealed class SplitNode {
  /// The sessions under this node, first to last - left to right and top
  /// to bottom.
  List<String> get leaves;
}

final class SplitLeaf extends SplitNode {
  SplitLeaf(this.id);

  final String id;

  @override
  List<String> get leaves => [id];
}

/// Two halves of the room [first] and [second] share, split along [axis];
/// [ratio] is the share [first] gets.
final class SplitBranch extends SplitNode {
  SplitBranch({
    required this.axis,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  });

  SplitAxis axis;
  SplitNode first;
  SplitNode second;
  double ratio;

  @override
  List<String> get leaves => [...first.leaves, ...second.leaves];
}

/// The least share of a split either half keeps, so neither can be dragged
/// away to nothing.
const double kMinSplitRatio = 0.15;
const double kMaxSplitRatio = 1 - kMinSplitRatio;

/// The axis that keeps two halves of [size] closest to its own shape: a
/// wide pane splits into two side by side, a tall one into two stacked.
SplitAxis splitAxisFor(Size size) =>
    size.width >= size.height ? SplitAxis.sideBySide : SplitAxis.stacked;

/// Each session's room in [root], as a share of a unit square: what the
/// keyboard moves focus across, and what a test can check a layout by.
Map<String, Rect> splitRects(SplitNode root, [Rect area = _unit]) {
  switch (root) {
    case SplitLeaf(:final id):
      return {id: area};
    case SplitBranch(:final axis, :final first, :final second, :final ratio):
      final (a, b) = _divide(area, axis, ratio);
      return {...splitRects(first, a), ...splitRects(second, b)};
  }
}

const Rect _unit = Rect.fromLTWH(0, 0, 1, 1);

(Rect, Rect) _divide(Rect area, SplitAxis axis, double ratio) {
  if (axis == SplitAxis.sideBySide) {
    final width = area.width * ratio;
    return (
      Rect.fromLTWH(area.left, area.top, width, area.height),
      Rect.fromLTWH(
        area.left + width,
        area.top,
        area.width - width,
        area.height,
      ),
    );
  }
  final height = area.height * ratio;
  return (
    Rect.fromLTWH(area.left, area.top, area.width, height),
    Rect.fromLTWH(
      area.left,
      area.top + height,
      area.width,
      area.height - height,
    ),
  );
}

/// The pane [direction] of [id] in [root]: of the panes past [id]'s edge
/// that share some of its span across that edge, the nearest - and among
/// those, the one that shares the most. Null at the edge of the layout.
String? splitNeighbor(SplitNode root, String id, SplitDirection direction) {
  final rects = splitRects(root);
  final from = rects[id];
  if (from == null) return null;
  const epsilon = 1e-9;
  String? best;
  var bestDistance = double.infinity;
  var bestOverlap = 0.0;
  for (final MapEntry(key: other, value: rect) in rects.entries) {
    if (other == id) continue;
    final double distance;
    final double overlap;
    switch (direction) {
      case SplitDirection.left:
        distance = from.left - rect.right;
        overlap =
            math.min(from.bottom, rect.bottom) - math.max(from.top, rect.top);
      case SplitDirection.right:
        distance = rect.left - from.right;
        overlap =
            math.min(from.bottom, rect.bottom) - math.max(from.top, rect.top);
      case SplitDirection.up:
        distance = from.top - rect.bottom;
        overlap =
            math.min(from.right, rect.right) - math.max(from.left, rect.left);
      case SplitDirection.down:
        distance = rect.top - from.bottom;
        overlap =
            math.min(from.right, rect.right) - math.max(from.left, rect.left);
    }
    if (distance < -epsilon || overlap <= epsilon) continue;
    final nearer = distance < bestDistance - epsilon;
    final asNear = (distance - bestDistance).abs() <= epsilon;
    if (nearer || (asNear && overlap > bestOverlap)) {
      best = other;
      bestDistance = distance;
      bestOverlap = overlap;
    }
  }
  return best;
}

/// [root] with the leaf [target] split in two: [target] and [newcomer]
/// along [axis], [newcomer] second unless [before].
SplitNode splitLeaf(
  SplitNode root,
  String target,
  String newcomer, {
  required SplitAxis axis,
  bool before = false,
  double ratio = 0.5,
}) {
  SplitNode visit(SplitNode node) {
    switch (node) {
      case SplitLeaf(:final id) when id == target:
        final added = SplitLeaf(newcomer);
        return SplitBranch(
          axis: axis,
          first: before ? added : node,
          second: before ? node : added,
          ratio: ratio,
        );
      case SplitLeaf():
        return node;
      case SplitBranch():
        node
          ..first = visit(node.first)
          ..second = visit(node.second);
        return node;
    }
  }

  return visit(root);
}

/// [root] without the leaf [id]: the half it shared a split with takes the
/// split's whole room. Null when [id] was all there was.
SplitNode? removeLeaf(SplitNode root, String id) {
  switch (root) {
    case SplitLeaf(id: final leaf):
      return leaf == id ? null : root;
    case SplitBranch():
      final first = removeLeaf(root.first, id);
      final second = removeLeaf(root.second, id);
      if (first == null) return second;
      if (second == null) return first;
      root
        ..first = first
        ..second = second;
      return root;
  }
}

/// The split [id] is a direct half of, or null at the root.
SplitBranch? parentOf(SplitNode root, String id) {
  if (root is! SplitBranch) return null;
  for (final child in [root.first, root.second]) {
    if (child is SplitLeaf && child.id == id) return root;
    final found = parentOf(child, id);
    if (found != null) return found;
  }
  return null;
}

/// The splits of [root] as records a save can hold and [splitLeaf] can play
/// back in the same order: each splits the first leaf of its first half
/// off from the first leaf of its second, root first.
List<({String first, String second, double ratio, SplitAxis axis})> splitSteps(
  SplitNode root,
) {
  if (root is! SplitBranch) return const [];
  return [
    (
      first: root.first.leaves.first,
      second: root.second.leaves.first,
      ratio: root.ratio,
      axis: root.axis,
    ),
    ...splitSteps(root.first),
    ...splitSteps(root.second),
  ];
}

/// A ready-made arrangement of a group's panes.
enum SplitPreset {
  /// Side by side, each as wide as the next.
  columns,

  /// One over another, each as tall as the next.
  rows,

  /// As square as the count allows: rows of columns, filled row by row.
  grid,

  /// The first pane large on the left, the rest stacked beside it.
  mainAndStack,
}

/// [ids], in that order, laid out as [preset] - the way the panes a group
/// already has are rearranged, nothing added or closed.
SplitNode presetLayout(List<String> ids, SplitPreset preset) {
  assert(ids.isNotEmpty);
  switch (preset) {
    case SplitPreset.columns:
      return _even(ids, SplitAxis.sideBySide);
    case SplitPreset.rows:
      return _even(ids, SplitAxis.stacked);
    case SplitPreset.grid:
      final perRow = math.sqrt(ids.length).ceil();
      final rows = [
        for (var i = 0; i < ids.length; i += perRow)
          _even(
            ids.sublist(i, math.min(i + perRow, ids.length)),
            SplitAxis.sideBySide,
          ),
      ];
      return _evenNodes(rows, SplitAxis.stacked);
    case SplitPreset.mainAndStack:
      if (ids.length == 1) return SplitLeaf(ids.single);
      return SplitBranch(
        axis: SplitAxis.sideBySide,
        ratio: 0.6,
        first: SplitLeaf(ids.first),
        second: _even(ids.sublist(1), SplitAxis.stacked),
      );
  }
}

SplitNode _even(List<String> ids, SplitAxis axis) =>
    _evenNodes([for (final id in ids) SplitLeaf(id)], axis);

/// [nodes] along [axis], each given the same share: the first takes 1/n and
/// the rest split what is left among themselves the same way.
SplitNode _evenNodes(List<SplitNode> nodes, SplitAxis axis) {
  if (nodes.length == 1) return nodes.single;
  return SplitBranch(
    axis: axis,
    ratio: 1 / nodes.length,
    first: nodes.first,
    second: _evenNodes(nodes.sublist(1), axis),
  );
}

/// The splits [id] sits under in [root], nearest first.
List<SplitBranch> ancestorsOf(SplitNode root, String id) {
  if (root is! SplitBranch) return const [];
  for (final child in [root.first, root.second]) {
    if (child.leaves.contains(id)) return [...ancestorsOf(child, id), root];
  }
  return const [];
}

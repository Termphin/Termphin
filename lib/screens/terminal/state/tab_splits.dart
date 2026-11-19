import 'split_layout.dart';

/// Which tabs share the screen: groups of them, each laid out as a tree of
/// splits ([SplitNode]) - two at most on a phone, up to [maxPanes] on a
/// desktop.
///
/// A group is one entry in the strip, and its sessions sit next to each
/// other in the strip's flat order, in the order their panes read - left to
/// right, top to bottom. Everything else is a function of that order, so the
/// screen keeps one list and the manager's persisted order needs no idea
/// that splits exist.
class TabSplits {
  TabSplits({this.maxPanes = 2});

  /// How many panes one group may hold.
  final int maxPanes;

  final Map<String, _Group> _groupOf = {};

  /// The share a two-pane split's first half keeps at least, and at most.
  static const double minRatio = 0.2;
  static const double maxRatio = 0.8;

  /// The tree [id]'s group is laid out as, or null when [id] stands alone.
  SplitNode? layoutOf(String id) => _groupOf[id]?.root;

  bool isSplit(String id) => _groupOf.containsKey(id);

  /// How many panes the group [id] is in has - one when it stands alone.
  int panesWith(String id) => _groupOf[id]?.root.leaves.length ?? 1;

  /// Share of its group's outermost split the first half gets - for a pair,
  /// the first session's share.
  double ratioOf(String id) {
    final root = _groupOf[id]?.root;
    return root is SplitBranch ? root.ratio : 0.5;
  }

  /// Sets the outermost split of [id]'s group, which for a pair is the only
  /// one.
  void setRatio(String id, double ratio) {
    final root = _groupOf[id]?.root;
    if (root is! SplitBranch) return;
    root.ratio = ratio.clamp(minRatio, maxRatio).toDouble();
  }

  /// Sets one split of a tree, dragged by its own divider.
  void setBranchRatio(SplitBranch branch, double ratio) =>
      branch.ratio = ratio.clamp(kMinSplitRatio, kMaxSplitRatio).toDouble();

  /// The strip's entries: a group where its sessions are, a single tab
  /// otherwise.
  List<List<String>> entries(List<String> order) {
    final result = <List<String>>[];
    final done = <_Group>{};
    for (final id in order) {
      final group = _groupOf[id];
      if (group == null) {
        result.add([id]);
      } else if (done.add(group)) {
        result.add([
          for (final leaf in group.root.leaves)
            if (order.contains(leaf)) leaf,
        ]);
      }
    }
    return result;
  }

  /// Whether [other] may join [target]'s pane: a session it is not already
  /// beside, in a group with room for one more.
  bool canJoin(String other, String target) {
    if (other == target) return false;
    final group = _groupOf[target];
    if (group != null && identical(group, _groupOf[other])) return false;
    return panesWith(target) < maxPanes;
  }

  /// Splits [target]'s pane with [other], which leaves any group it was in
  /// and lands beside [target] along [axis] - after it, unless [before].
  List<String> join(
    List<String> order,
    String other,
    String target, {
    SplitAxis axis = SplitAxis.sideBySide,
    bool before = false,
    double ratio = 0.5,
  }) {
    if (!canJoin(other, target)) return order;
    _leave(other);
    final group = _groupOf[target] ?? _Group(SplitLeaf(target));
    group.root = splitLeaf(
      group.root,
      target,
      other,
      axis: axis,
      before: before,
      ratio: ratio,
    );
    for (final leaf in group.root.leaves) {
      _groupOf[leaf] = group;
    }
    final next = [...order]..remove(other);
    next.insert(next.indexOf(target) + 1, other);
    return _normalize(next);
  }

  /// Moves the entry at [oldIndex] to [newIndex] - both counted in entries,
  /// so a group travels whole.
  List<String> reorder(List<String> order, int oldIndex, int newIndex) {
    final list = entries(order);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    return [for (final entry in list) ...entry];
  }

  /// Swaps the two halves of the split [id] is directly in. Each keeps its
  /// own size, so the divider moves with them.
  List<String> swap(List<String> order, String id) {
    final root = _groupOf[id]?.root;
    if (root == null) return order;
    final parent = parentOf(root, id);
    if (parent == null) return order;
    final first = parent.first;
    parent
      ..first = parent.second
      ..second = first
      ..ratio = 1 - parent.ratio;
    return _normalize(order);
  }

  /// The pane [direction] of [id] in its group, if there is one.
  String? neighbor(String id, SplitDirection direction) {
    final root = _groupOf[id]?.root;
    return root == null ? null : splitNeighbor(root, id, direction);
  }

  /// Every group in [order] as split steps, for saving. A pair is one step;
  /// the axis is left out where only two panes fit - a phone, whose
  /// orientation decides it.
  List<({String first, String second, double ratio, String? axis})> saved(
    List<String> order,
  ) {
    final done = <_Group>{};
    return [
      for (final id in order)
        if (_groupOf[id] case final group? when done.add(group))
          for (final step in splitSteps(group.root))
            (
              first: step.first,
              second: step.second,
              ratio: step.ratio,
              axis: maxPanes > 2 ? step.axis.name : null,
            ),
    ];
  }

  /// Takes [id] out of its group and leaves it a tab of its own; the rest of
  /// the group closes over the gap.
  void detach(String id) => _leave(id);

  /// Drops [ids] from every group they were in - the tabs are gone.
  void forget(Iterable<String> ids) => ids.forEach(_leave);

  void _leave(String id) {
    final group = _groupOf.remove(id);
    if (group == null) return;
    final rest = removeLeaf(group.root, id);
    if (rest == null || rest is SplitLeaf) {
      for (final leaf in rest?.leaves ?? const <String>[]) {
        _groupOf.remove(leaf);
      }
      return;
    }
    group.root = rest;
  }

  /// [order] with each group's sessions together, where its first one was,
  /// in the order its panes read.
  List<String> _normalize(List<String> order) {
    final result = <String>[];
    final done = <_Group>{};
    for (final id in order) {
      final group = _groupOf[id];
      if (group == null) {
        result.add(id);
      } else if (done.add(group)) {
        result.addAll(group.root.leaves.where(order.contains));
      }
    }
    return result;
  }
}

class _Group {
  _Group(this.root);

  SplitNode root;
}

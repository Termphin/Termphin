/// Which tabs share the screen, two at a time.
///
/// A split is one entry in the strip, and its two sessions sit next to each
/// other in the strip's flat order - first of the two on top, or on the left.
/// Everything here is a function of that order, so the screen keeps one list
/// and the manager's persisted order needs no idea that splits exist.
class TabSplits {
  final Map<String, String> _partner = {};
  final Map<String, double> _ratio = {};

  static const double minRatio = 0.2;
  static const double maxRatio = 0.8;

  String? partnerOf(String id) => _partner[id];

  bool isSplit(String id) => _partner.containsKey(id);

  /// Share of the split the first session gets.
  double ratioOf(String id) => _ratio[id] ?? 0.5;

  void setRatio(String id, double ratio) {
    final partner = _partner[id];
    if (partner == null) return;
    final clamped = ratio.clamp(minRatio, maxRatio).toDouble();
    _ratio[id] = clamped;
    _ratio[partner] = clamped;
  }

  /// The strip's entries: a pair where two partners are adjacent, a single
  /// tab otherwise.
  List<List<String>> entries(List<String> order) {
    final result = <List<String>>[];
    for (var i = 0; i < order.length; i++) {
      final id = order[i];
      if (i + 1 < order.length && _partner[id] == order[i + 1]) {
        result.add([id, order[i + 1]]);
        i++;
      } else {
        result.add([id]);
      }
    }
    return result;
  }

  /// Whether [other] may make a split with [target].
  bool canJoin(String other, String target) =>
      other != target && !isSplit(target);

  /// Splits [target] with [other], which leaves any split it was in and lands
  /// second, beside [target].
  List<String> join(List<String> order, String other, String target) {
    if (!canJoin(other, target)) return order;
    _unpair(other);
    final next = [...order]..remove(other);
    next.insert(next.indexOf(target) + 1, other);
    _partner[target] = other;
    _partner[other] = target;
    return next;
  }

  /// Moves the entry at [oldIndex] to [newIndex] - both counted in entries,
  /// so a split travels whole.
  List<String> reorder(List<String> order, int oldIndex, int newIndex) {
    final list = entries(order);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    return [for (final entry in list) ...entry];
  }

  /// Swaps the two halves of the split [id] is in. Each pane keeps its own
  /// size, so the divider moves with them.
  List<String> swap(List<String> order, String id) {
    final partner = _partner[id];
    if (partner == null) return order;
    final next = [...order];
    final a = next.indexOf(id);
    final b = next.indexOf(partner);
    next[a] = partner;
    next[b] = id;
    setRatio(id, 1 - ratioOf(id));
    return next;
  }

  /// Every split in [order], for saving.
  List<({String first, String second, double ratio})> saved(
    List<String> order,
  ) => [
    for (final entry in entries(order))
      if (entry.length == 2)
        (first: entry.first, second: entry.last, ratio: ratioOf(entry.first)),
  ];

  /// Ends the split [id] is in. Both stay where they were, as two tabs.
  void detach(String id) => _unpair(id);

  /// Drops every split one of [ids] was in - the tabs are gone.
  void forget(Iterable<String> ids) => ids.forEach(_unpair);

  void _unpair(String id) {
    final partner = _partner.remove(id);
    _ratio.remove(id);
    if (partner != null) {
      _partner.remove(partner);
      _ratio.remove(partner);
    }
  }
}

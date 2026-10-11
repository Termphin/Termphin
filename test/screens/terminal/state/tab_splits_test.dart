import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/screens/terminal/state/tab_splits.dart';

void main() {
  test('a join puts the dragged tab beside the target as one entry', () {
    final splits = TabSplits();
    final order = splits.join(['a', 'b', 'c'], 'a', 'c');

    expect(order, ['b', 'c', 'a']);
    expect(splits.entries(order), [
      ['b'],
      ['c', 'a'],
    ]);
  });

  test('a split is full: nothing joins a tab already in one', () {
    final splits = TabSplits();
    final order = splits.join(['a', 'b', 'c'], 'b', 'a');

    expect(splits.canJoin('c', 'a'), isFalse);
    expect(splits.join(order, 'c', 'a'), order);
  });

  test('a reorder moves a split whole', () {
    final splits = TabSplits();
    final order = splits.join(['a', 'b', 'c'], 'b', 'a');

    expect(splits.reorder(order, 0, 1), ['c', 'a', 'b']);
    expect(splits.reorder(order, 1, 0), ['c', 'a', 'b']);
  });

  test('joining a pane of one split to another tab dissolves the first', () {
    final splits = TabSplits();
    var order = splits.join(['a', 'b', 'c'], 'b', 'a');
    order = splits.join(order, 'b', 'c');

    expect(splits.partnerOf('a'), isNull);
    expect(splits.entries(order), [
      ['a'],
      ['c', 'b'],
    ]);
  });

  test('a swap trades the halves and each keeps its size', () {
    final splits = TabSplits();
    var order = splits.join(['a', 'b', 'c'], 'b', 'a');
    splits.setRatio('a', 0.3);
    order = splits.swap(order, 'a');

    expect(order, ['b', 'a', 'c']);
    expect(splits.entries(order).first, ['b', 'a']);
    expect(splits.ratioOf('b'), closeTo(0.7, 1e-9));
  });

  test('closing one half leaves the other as a plain tab', () {
    final splits = TabSplits();
    splits.join(['a', 'b'], 'b', 'a');
    splits.forget(['b']);

    expect(splits.isSplit('a'), isFalse);
    expect(splits.entries(['a']), [
      ['a'],
    ]);
  });

  test('the divider cannot squeeze a pane out of sight', () {
    final splits = TabSplits();
    splits.join(['a', 'b'], 'b', 'a');
    splits.setRatio('a', 0.05);

    expect(splits.ratioOf('a'), TabSplits.minRatio);
    expect(splits.ratioOf('b'), TabSplits.minRatio);
  });

  test('what is saved is each split, first half first, with its divider', () {
    final splits = TabSplits();
    final order = splits.join(['a', 'b', 'c'], 'c', 'a');
    splits.setRatio('a', 0.3);

    expect(splits.saved(order), [(first: 'a', second: 'c', ratio: 0.3)]);
  });
}

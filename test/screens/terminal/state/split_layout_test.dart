import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/screens/terminal/state/split_layout.dart';
import 'package:termphin/screens/terminal/state/tab_splits.dart';

/// A 2x2 grid: a over c on the left, b over d on the right.
SplitNode _grid() => SplitBranch(
  axis: SplitAxis.sideBySide,
  first: SplitBranch(
    axis: SplitAxis.stacked,
    first: SplitLeaf('a'),
    second: SplitLeaf('c'),
  ),
  second: SplitBranch(
    axis: SplitAxis.stacked,
    first: SplitLeaf('b'),
    second: SplitLeaf('d'),
  ),
);

void main() {
  group('the layout', () {
    test('a grid gives each pane its quarter', () {
      final rects = splitRects(_grid());
      expect(rects['a'], const Rect.fromLTWH(0, 0, 0.5, 0.5));
      expect(rects['c'], const Rect.fromLTWH(0, 0.5, 0.5, 0.5));
      expect(rects['b'], const Rect.fromLTWH(0.5, 0, 0.5, 0.5));
      expect(rects['d'], const Rect.fromLTWH(0.5, 0.5, 0.5, 0.5));
    });

    test('the panes read left to right, top to bottom', () {
      expect(_grid().leaves, ['a', 'c', 'b', 'd']);
    });

    test('a wide pane splits side by side, a tall one stacks', () {
      expect(splitAxisFor(const Size(800, 400)), SplitAxis.sideBySide);
      expect(splitAxisFor(const Size(400, 800)), SplitAxis.stacked);
    });
  });

  group('moving between panes', () {
    test('each arrow finds the pane on that side', () {
      final grid = _grid();
      expect(splitNeighbor(grid, 'a', SplitDirection.right), 'b');
      expect(splitNeighbor(grid, 'a', SplitDirection.down), 'c');
      expect(splitNeighbor(grid, 'd', SplitDirection.left), 'c');
      expect(splitNeighbor(grid, 'd', SplitDirection.up), 'b');
    });

    test('there is nothing past the edge', () {
      expect(splitNeighbor(_grid(), 'a', SplitDirection.left), isNull);
      expect(splitNeighbor(_grid(), 'a', SplitDirection.up), isNull);
    });

    test('from a tall pane, the one beside it that shares the most', () {
      final layout = SplitBranch(
        axis: SplitAxis.sideBySide,
        first: SplitLeaf('main'),
        second: SplitBranch(
          axis: SplitAxis.stacked,
          ratio: 0.7,
          first: SplitLeaf('top'),
          second: SplitLeaf('bottom'),
        ),
      );
      expect(splitNeighbor(layout, 'main', SplitDirection.right), 'top');
      expect(splitNeighbor(layout, 'bottom', SplitDirection.left), 'main');
    });
  });

  group('changing the tree', () {
    test('a pane removed from the middle leaves its neighbour its room', () {
      final rest = removeLeaf(_grid(), 'c')!;
      expect(rest.leaves, ['a', 'b', 'd']);
      expect(splitRects(rest)['a'], const Rect.fromLTWH(0, 0, 0.5, 1));
    });

    test('the steps of a tree play back into the same tree', () {
      final grid = _grid();
      final steps = splitSteps(grid);
      SplitNode replayed = SplitLeaf(steps.first.first);
      for (final step in steps) {
        replayed = splitLeaf(
          replayed,
          step.first,
          step.second,
          axis: step.axis,
          ratio: step.ratio,
        );
      }
      expect(splitRects(replayed), splitRects(grid));
    });
  });

  group('groups of more than two', () {
    test('up to the limit, then full', () {
      final splits = TabSplits(maxPanes: 3);
      var order = splits.join(['a', 'b', 'c', 'd'], 'b', 'a');
      order = splits.join(order, 'c', 'b', axis: SplitAxis.stacked);

      expect(splits.entries(order), [
        ['a', 'b', 'c'],
        ['d'],
      ]);
      expect(splits.canJoin('d', 'a'), isFalse);
    });

    test('closing one pane keeps the rest together', () {
      final splits = TabSplits(maxPanes: 4);
      var order = splits.join(['a', 'b', 'c'], 'b', 'a');
      order = splits.join(order, 'c', 'b', axis: SplitAxis.stacked);
      splits.detach('b');

      expect(splits.entries(order), [
        ['a', 'c'],
        ['b'],
      ]);
      expect(splits.isSplit('b'), isFalse);
    });

    test('a group is saved with its directions and comes back the same', () {
      final splits = TabSplits(maxPanes: 4);
      var order = splits.join(['a', 'b', 'c', 'd'], 'b', 'a');
      order = splits.join(order, 'c', 'a', axis: SplitAxis.stacked);
      order = splits.join(order, 'd', 'b', axis: SplitAxis.stacked);
      final saved = splits.saved(order);

      final restored = TabSplits(maxPanes: 4);
      var again = ['a', 'b', 'c', 'd'];
      for (final step in saved) {
        again = restored.join(
          again,
          step.second,
          step.first,
          axis: SplitAxis.values.byName(step.axis!),
          ratio: step.ratio,
        );
      }

      expect(
        splitRects(restored.layoutOf('a')!),
        splitRects(splits.layoutOf('a')!),
      );
    });

    test('a phone saves a pair without a direction', () {
      final splits = TabSplits();
      final order = splits.join(['a', 'b'], 'b', 'a');
      expect(splits.saved(order).single.axis, isNull);
    });
  });
}

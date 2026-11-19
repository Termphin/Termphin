import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/screens/terminal/state/split_layout.dart';
import 'package:termphin/widgets/terminal/split_pane_chrome.dart';
import 'package:termphin/widgets/terminal/split_tree_layout.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

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
  final profile = profileFixture();

  testWidgets('lays out a 2x2 tree into four quadrants and reports sizes', (
    tester,
  ) async {
    final sizes = <String, Size>{};
    await pumpTestApp(
      tester,
      SizedBox(
        width: 810,
        height: 610,
        child: SplitTreeLayout(
          root: _grid(),
          paneBuilder: (id) => SizedBox.expand(child: Text('pane-$id')),
          focusedId: 'a',
          profileFor: (_) => profile,
          labelFor: (id) => 'label-$id',
          onFocusPane: (_) {},
          onRatioChanged: (_, _) {},
          onDividerHeldChanged: (_) {},
          onPaneSized: (id, size) => sizes[id] = size,
        ),
      ),
    );
    tester.view.physicalSize = const Size(810, 610);
    await tester.pumpAndSettle();

    final a = tester.getRect(find.byKey(const ValueKey('splitTreePane-a')));
    final b = tester.getRect(find.byKey(const ValueKey('splitTreePane-b')));
    final c = tester.getRect(find.byKey(const ValueKey('splitTreePane-c')));
    final d = tester.getRect(find.byKey(const ValueKey('splitTreePane-d')));

    expect(a.right, lessThan(b.left));
    expect(c.right, lessThan(d.left));
    expect(a.bottom, lessThan(c.top));
    expect(b.bottom, lessThan(d.top));
    expect(sizes.keys, containsAll(['a', 'b', 'c', 'd']));
    expect(sizes['a'], const Size(400, 300));
  });

  testWidgets('clicking an unfocused pane or its header focuses it', (
    tester,
  ) async {
    final focused = <String>[];
    await pumpTestApp(
      tester,
      SizedBox(
        width: 810,
        height: 400,
        child: SplitTreeLayout(
          root: SplitBranch(
            axis: SplitAxis.sideBySide,
            first: SplitLeaf('a'),
            second: SplitLeaf('b'),
          ),
          paneBuilder: (id) => Container(
            color: const Color(0x00000000),
            child: Center(child: Text('body-$id')),
          ),
          focusedId: 'a',
          profileFor: (_) => profile,
          labelFor: (id) => 'header-$id',
          onFocusPane: focused.add,
          onRatioChanged: (_, _) {},
          onDividerHeldChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('body-b'));
    await tester.pump();
    expect(focused, ['b']);

    await tester.tap(find.text('header-a'));
    await tester.pump();
    expect(focused, ['b', 'a']);
  });

  testWidgets('dragging a divider updates its branch ratio and hold state', (
    tester,
  ) async {
    final branch = SplitBranch(
      axis: SplitAxis.sideBySide,
      first: SplitLeaf('a'),
      second: SplitLeaf('b'),
    );
    final ratios = <double>[];
    final heldStates = <bool>[];

    await pumpTestApp(
      tester,
      SizedBox(
        width: 810,
        height: 400,
        child: SplitTreeLayout(
          root: branch,
          paneBuilder: (id) => SizedBox.expand(child: Text('pane-$id')),
          focusedId: 'a',
          profileFor: (_) => profile,
          labelFor: (id) => 'label-$id',
          onFocusPane: (_) {},
          onRatioChanged: (b, ratio) {
            expect(identical(b, branch), isTrue);
            ratios.add(ratio);
          },
          onDividerHeldChanged: heldStates.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final divider = tester.getCenter(find.byType(SplitDivider));
    await tester.dragFrom(divider, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(heldStates.first, isTrue);
    expect(heldStates.last, isFalse);
    expect(ratios, isNotEmpty);
    expect(ratios.last, greaterThan(0.5));
  });

  testWidgets('zoomedId fills the layout with that single pane', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      SizedBox(
        width: 810,
        height: 400,
        child: SplitTreeLayout(
          root: SplitBranch(
            axis: SplitAxis.sideBySide,
            first: SplitLeaf('a'),
            second: SplitLeaf('b'),
          ),
          paneBuilder: (id) => SizedBox.expand(child: Text('pane-$id')),
          focusedId: 'b',
          zoomedId: 'b',
          profileFor: (_) => profile,
          labelFor: (id) => 'label-$id',
          onFocusPane: (_) {},
          onRatioChanged: (_, _) {},
          onDividerHeldChanged: (_) {},
        ),
      ),
    );
    tester.view.physicalSize = const Size(810, 400);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('splitTreePane-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('splitTreePane-a')), findsNothing);
    expect(find.byType(SplitDivider), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('splitTreePane-b'))),
      const Size(810, 400),
    );
  });
}

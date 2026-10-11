import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/terminal/action_dock_menu.dart';
import 'package:termphin/widgets/ui/action_dock_tile.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SpotlightTool tool(String label, {VoidCallback? onSelect}) => SpotlightTool(
    icon: Icons.bolt,
    label: label,
    onSelect: onSelect ?? () {},
  );

  Future<void> openMenu(
    WidgetTester tester, {
    required List<SpotlightTool> tools,
  }) async {
    final buttonKey = GlobalKey();
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TextButton(
              key: buttonKey,
              onPressed: () {
                final box =
                    buttonKey.currentContext!.findRenderObject() as RenderBox;
                showActionDockMenu(
                  context,
                  anchorRect: box.localToGlobal(Offset.zero) & box.size,
                  tools: tools,
                );
              },
              child: const Text('Open palette'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open palette'));
    await tester.pumpAndSettle();
  }

  testWidgets('dismissActionDockMenu closes the open menu and says so', (
    tester,
  ) async {
    await openMenu(tester, tools: [tool('Paste')]);
    expect(find.text('Paste'), findsOneWidget);

    expect(dismissActionDockMenu(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);

    expect(dismissActionDockMenu(), isFalse);
  });

  testWidgets('a menu closed by a tap outside is not closed again', (
    tester,
  ) async {
    await openMenu(tester, tools: [tool('Paste')]);
    await tester.tapAt(const Offset(700, 900));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);

    expect(dismissActionDockMenu(), isFalse);
  });

  testWidgets('lists every tool as a grid tile', (tester) async {
    await openMenu(tester, tools: [tool('Upload file'), tool('Paste')]);

    expect(find.text('Upload file'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('tapping a tile runs its action and closes the menu', (
    tester,
  ) async {
    var ran = false;

    await openMenu(
      tester,
      tools: [tool('Upload file', onSelect: () => ran = true)],
    );

    await tester.tap(find.text('Upload file'));
    await tester.pumpAndSettle();

    expect(ran, isTrue);
    expect(find.text('Upload file'), findsNothing);
  });

  testWidgets(
    'a disabled tool still runs its action, dimmed rather than absent',
    (tester) async {
      var ran = false;

      await openMenu(
        tester,
        tools: [
          SpotlightTool(
            icon: Icons.bolt,
            label: 'Upload file',
            enabled: false,
            onSelect: () => ran = true,
          ),
        ],
      );

      final tile = tester.widget<ActionDockTile>(find.byType(ActionDockTile));
      expect(tile.dimmed, isTrue);

      await tester.tap(find.text('Upload file'));
      await tester.pumpAndSettle();

      expect(ran, isTrue);
    },
  );

  testWidgets('a single row of tools makes a single-row panel', (tester) async {
    await openMenu(tester, tools: [tool('One'), tool('Two'), tool('Three')]);

    final size = tester.getSize(find.byType(ActionDockPanel));
    expect(size.width, kPalettePanelWidth);
    expect(size.height, palettePanelHeight(1));
  });

  testWidgets('the panel grows a row at a time', (tester) async {
    await openMenu(
      tester,
      tools: [for (var i = 0; i < 6; i++) tool('Tool $i')],
    );

    expect(
      tester.getSize(find.byType(ActionDockPanel)).height,
      palettePanelHeight(2),
    );
  });

  testWidgets('past three rows it caps and scrolls instead of growing', (
    tester,
  ) async {
    await openMenu(
      tester,
      tools: [for (var i = 0; i < 12; i++) tool('Tool $i')],
    );

    expect(
      tester.getSize(find.byType(ActionDockPanel)).height,
      palettePanelHeight(3),
    );
    final scrollView = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(ActionDockPanel),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scrollView.physics, isA<ClampingScrollPhysics>());
  });

  testWidgets('a panel that fits does not scroll', (tester) async {
    await openMenu(tester, tools: [tool('One'), tool('Two')]);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(ActionDockPanel),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
  });
}

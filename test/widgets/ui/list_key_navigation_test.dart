import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/ui/list_key_navigation.dart';

import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

/// Three rows, each with a button inside it the way a card has its `⋮`.
class _Rows extends StatelessWidget {
  const _Rows({
    required this.rows,
    required this.buttons,
    required this.opened,
  });

  final List<FocusNode> rows;
  final List<FocusNode> buttons;
  final List<int> opened;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListKeyNavigation(
      child: ListView(
        children: [
          for (var i = 0; i < rows.length; i++)
            InkWell(
              focusNode: rows[i],
              onTap: () => opened.add(i),
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(child: Text('row $i')),
                    IconButton(
                      focusNode: buttons[i],
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

void main() {
  late List<FocusNode> rows;
  late List<FocusNode> buttons;
  late List<int> opened;

  setUp(() {
    rows = List.generate(3, (i) => FocusNode(debugLabel: 'row $i'));
    buttons = List.generate(3, (i) => FocusNode(debugLabel: 'button $i'));
    opened = [];
  });

  tearDown(() {
    for (final node in [...rows, ...buttons]) {
      node.dispose();
    }
  });

  Future<void> pump(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      _Rows(rows: rows, buttons: buttons, opened: opened),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Down walks the rows, not the buttons inside them', (
    tester,
  ) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(rows[0].hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(rows[1].hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(rows[0].hasPrimaryFocus, isTrue);
  }, variant: _desktop);

  testWidgets('End and Home jump to the last and first row', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(rows[2].hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(rows[0].hasPrimaryFocus, isTrue);
  }, variant: _desktop);

  testWidgets('Enter opens the row the keys are on', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened, [1]);
  }, variant: _desktop);

  testWidgets('the arrows are heard again after a click on empty space', (
    tester,
  ) async {
    await pump(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tapAt(const Offset(400, 600));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(rows[0].hasPrimaryFocus, isTrue);
  }, variant: _desktop);

  testWidgets('a phone is left as it was', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();

    expect(rows.any((node) => node.hasPrimaryFocus), isFalse);
  });
}

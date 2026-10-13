import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/widgets/ui/context_bar.dart';

import '../../support/test_app.dart';

void main() {
  final fired = <String>[];

  setUp(fired.clear);

  ContextBarAction action(String label, IconData icon, {bool enabled = true}) =>
      ContextBarAction(
        icon: icon,
        label: label,
        onPressed: enabled ? () => fired.add(label) : null,
      );

  Future<void> pump(WidgetTester tester, double width, ContextBar bar) =>
      pumpTestApp(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: bar),
          ),
        ),
      );

  ContextBar bar({List<ContextBarAction> menu = const []}) => ContextBar(
    leading: const Icon(PhosphorIconsRegular.x),
    title: '3 selected',
    actions: [
      action('Copy', PhosphorIconsRegular.copy),
      action('Move', PhosphorIconsRegular.arrowsLeftRight),
      action('Delete', PhosphorIconsRegular.trash),
    ],
    menu: menu,
  );

  testWidgets('every action sits on a bar wide enough for it', (tester) async {
    await pump(tester, 400, bar());

    expect(find.byTooltip('More'), findsNothing);
    await tester.tap(find.byTooltip('Delete'));
    expect(fired, ['Delete']);
  });

  testWidgets('what does not fit moves into More, from the end', (
    tester,
  ) async {
    await pump(tester, 260, bar());

    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(fired, ['Delete']);
  });

  testWidgets('menu actions always go to More', (tester) async {
    await pump(
      tester,
      400,
      bar(menu: [action('Select all', PhosphorIconsRegular.checks)]),
    );

    expect(find.byTooltip('Delete'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(fired, ['Select all']);
  });

  testWidgets('an action without a handler is greyed out', (tester) async {
    await pump(
      tester,
      400,
      ContextBar(
        leading: const SizedBox(),
        title: 'Nothing selected',
        actions: [
          action('Move', PhosphorIconsRegular.arrowsLeftRight, enabled: false),
        ],
      ),
    );

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(PhosphorIconsRegular.arrowsLeftRight),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}

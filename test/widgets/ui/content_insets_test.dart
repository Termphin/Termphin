import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ui/large_title_scaffold.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget scaffold() => LargeTitleScaffold(
    title: 'Title',
    bodyBuilder: (context, controller, gutter) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32).add(gutter),
      children: const [SizedBox(height: 2000, child: Text('body'))],
    ),
  );

  testWidgets('scroll body ends above the system navigation bar', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await pumpTestApp(tester, scaffold());

    expect(tester.getBottomLeft(find.byType(ListView)).dy, 1000 - 48);
  });

  testWidgets('a wide window centres the content without boxing the scroll '
      'view', (tester) async {
    await pumpTestApp(tester, scaffold());
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ListView)).width, 1400);

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    await tester.dragFrom(const Offset(40, 400), const Offset(0, -200));
    await tester.pump();
    expect(controller.offset, greaterThan(0));

    final text = tester.getRect(find.text('body'));
    expect(text.left, (1400 - kContentMaxWidth) / 2 + 16);
    expect(text.right, 1400 - (1400 - kContentMaxWidth) / 2 - 16);
  });
}

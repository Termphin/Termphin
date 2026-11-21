import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ui/modal_actions.dart';

import '../../support/test_app.dart';

Widget _host() => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(20),
    child: ModalActions(
      layout: ModalActionsLayout.sideBySide,
      secondary: OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
      primary: FilledButton(onPressed: () {}, child: const Text('Run')),
    ),
  ),
);

void main() {
  testWidgets('on a desktop the buttons keep their own width, at the right, '
      'the primary last', (tester) async {
    await pumpTestApp(tester, _host());

    final run = tester.getRect(find.widgetWithText(FilledButton, 'Run'));
    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    expect(run.width, lessThan(200));
    expect(run.right, 780);
    expect(cancel.right, lessThan(run.left));
    expect(run.height, AppTheme.desktopControlHeight);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('on a phone they share the full width', (tester) async {
    await pumpTestApp(tester, _host());
    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();

    final run = tester.getRect(find.widgetWithText(FilledButton, 'Run'));
    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    expect(cancel.left, 20);
    expect(run.right, 380);
    expect(run.width, greaterThan(150));
  });

  testWidgets('wider than a phone they stop at the button width, centred', (
    tester,
  ) async {
    await pumpTestApp(tester, _host());

    final run = tester.getRect(find.widgetWithText(FilledButton, 'Run'));
    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    expect(run.right - cancel.left, AppTheme.buttonMaxWidth);
    expect((cancel.left + run.right) / 2, 400);
  });

  testWidgets('a lone button grows to the button width, no further, where '
      'it is put', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: ButtonWidth(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: () {}, child: const Text('Go')),
        ),
      ),
    );

    final go = tester.getRect(find.widgetWithText(FilledButton, 'Go'));
    expect(go.left, 0);
    expect(go.width, AppTheme.buttonMaxWidth);
  });
}

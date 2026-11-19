import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/widgets/settings/pin_setup_dialog.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('a PIN is typed, confirmed and handed back', (tester) async {
    String? chosen;
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => chosen = await showDialog<String>(
            context: context,
            builder: (_) => const PinSetupDialog(),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Future<void> type(List<LogicalKeyboardKey> keys) async {
      for (final key in keys) {
        await tester.sendKeyEvent(key);
      }
      await tester.pumpAndSettle();
    }

    const one = LogicalKeyboardKey.digit1;
    const two = LogicalKeyboardKey.digit2;
    const three = LogicalKeyboardKey.numpad3;
    const four = LogicalKeyboardKey.digit4;
    await type([one, two, three, four, LogicalKeyboardKey.enter]);
    await type([one, two, three, four]);

    expect(chosen, '1234');
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
}

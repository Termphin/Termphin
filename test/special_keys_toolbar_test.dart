import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/widgets/terminal/special_keys_toolbar.dart';

import 'support/test_app.dart';

void main() {
  test('normalizes unsupported and duplicate toolbar actions', () {
    final normalized = normalizeToolbarOrder([
      'esc',
      'unsupported_action',
      'esc',
      'tab',
    ]);

    expect(normalized, hasLength(kToolbarSlotCount));
    expect(normalized.where((id) => id == 'esc'), hasLength(1));
    expect(normalized, isNot(contains('unsupported_action')));
    expect(normalized, contains('tab'));
  });

  testWidgets('follows layout edits made while it stays mounted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ctrlNotifier = ValueNotifier(CtrlMode.off);
    addTearDown(ctrlNotifier.dispose);
    final altNotifier = ValueNotifier(AltMode.off);
    addTearDown(altNotifier.dispose);

    await pumpTestApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SpecialKeysToolbar(
            onKey: (_) {},
            ctrlNotifier: ctrlNotifier,
            altNotifier: altNotifier,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ESC'), findsOneWidget);

    await saveToolbarLayout(
      ToolbarLayout(
        order: ['ctrl_c', ...List.filled(kToolbarSlotCount - 1, '')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ctrl+C'), findsOneWidget);
    expect(find.text('ESC'), findsNothing);
  });

  testWidgets('shift changes what tab sends and clears after one key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ctrlNotifier = ValueNotifier(CtrlMode.off);
    addTearDown(ctrlNotifier.dispose);
    final altNotifier = ValueNotifier(AltMode.off);
    addTearDown(altNotifier.dispose);
    final shiftNotifier = ValueNotifier(ShiftMode.off);
    addTearDown(shiftNotifier.dispose);
    final sent = <List<int>>[];

    await saveToolbarLayout(
      ToolbarLayout(
        order: ['shift', 'tab', ...List.filled(kToolbarSlotCount - 2, '')],
      ),
    );

    await pumpTestApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SpecialKeysToolbar(
            onKey: (data) => sent.add(data.toList()),
            ctrlNotifier: ctrlNotifier,
            altNotifier: altNotifier,
            shiftNotifier: shiftNotifier,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SHIFT'));
    await tester.pump();
    expect(shiftNotifier.value, ShiftMode.oneshot);

    await tester.tap(find.text('TAB'));
    await tester.pump();
    expect(sent, [
      [0x1b, 0x5b, 0x5a],
    ]);
    expect(shiftNotifier.value, ShiftMode.off);

    await tester.tap(find.text('TAB'));
    await tester.pump();
    expect(sent.last, [0x09]);
  });

  testWidgets('symbol keys send their character', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctrlNotifier = ValueNotifier(CtrlMode.off);
    addTearDown(ctrlNotifier.dispose);
    final altNotifier = ValueNotifier(AltMode.off);
    addTearDown(altNotifier.dispose);
    final sent = <List<int>>[];

    await saveToolbarLayout(
      ToolbarLayout(
        order: ['sym_pipe', ...List.filled(kToolbarSlotCount - 1, '')],
      ),
    );

    await pumpTestApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SpecialKeysToolbar(
            onKey: (data) => sent.add(data.toList()),
            ctrlNotifier: ctrlNotifier,
            altNotifier: altNotifier,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('|'));
    await tester.pump();

    expect(sent, [
      [0x7c],
    ]);
  });
}

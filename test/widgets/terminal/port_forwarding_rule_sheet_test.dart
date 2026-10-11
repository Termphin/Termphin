import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/port_forwarding_rule.dart';
import 'package:termphin/widgets/terminal/port_forwarding_rule_sheet.dart';

import '../../support/test_app.dart';

Future<void> _openSheet(
  WidgetTester tester,
  ValueNotifier<PortForwardingRule?> result, {
  PortForwardingRule? existing,
}) async {
  await pumpTestApp(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result.value = await showPortForwardingRuleSheet(
              context: context,
              title: 'Add Tunnel',
              existing: existing,
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an edited rule keeps its id and creation time', (tester) async {
    final existing = PortForwardingRule(
      id: 'rule-1',
      name: 'Database',
      type: ForwardType.local,
      localPort: 15432,
      remoteHost: 'db.internal',
      remotePort: 5432,
      createdAt: DateTime.utc(2026, 2, 3),
    );
    final result = ValueNotifier<PortForwardingRule?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, result, existing: existing);

    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(0)).controller?.text, 'Database');
    expect(tester.widget<TextField>(fields.at(1)).controller?.text, '15432');
    expect(
      tester.widget<TextField>(fields.at(2)).controller?.text,
      'db.internal',
    );

    await tester.enterText(fields.at(1), '15433');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(result.value!.id, 'rule-1');
    expect(result.value!.createdAt, DateTime.utc(2026, 2, 3));
    expect(result.value!.localPort, 15433);
  });

  testWidgets('creates a local forwarding rule from entered values', (
    tester,
  ) async {
    final result = ValueNotifier<PortForwardingRule?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, result);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'Database');
    await tester.enterText(fields.at(1), '15432');
    await tester.enterText(fields.at(2), 'db.internal');
    await tester.enterText(fields.at(3), '5432');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value!.type, ForwardType.local);
    expect(result.value!.name, 'Database');
    expect(result.value!.localPort, 15432);
    expect(result.value!.remoteHost, 'db.internal');
    expect(result.value!.remotePort, 5432);
    expect(result.value!.localHost, 'localhost');
    expect(result.value!.id, isNotEmpty);
  });

  testWidgets('keeps the sheet open when a port is invalid', (tester) async {
    final result = ValueNotifier<PortForwardingRule?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, result);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '0');
    await tester.enterText(fields.at(3), '70000');
    await tester.pump();

    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save'),
    );
    expect(save.onPressed, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();

    expect(result.value, isNull);
    expect(find.text('Add Tunnel'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/widgets/groups/group_section_header.dart';

import '../../support/test_app.dart';

void main() {
  const group = ProfileGroup(name: 'Servers', colorHex: '4DA3FF');
  final loadButton = find.byKey(const ValueKey('groupLoadSessionsButton'));

  testWidgets('no load button without a handler', (tester) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: GroupSectionHeader(
          group: group,
          count: 2,
          onAdd: () {},
          addTooltip: 'Add machine',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadButton, findsNothing);
  });

  testWidgets('load button calls its handler', (tester) async {
    var loads = 0;
    await pumpTestApp(
      tester,
      Scaffold(
        body: GroupSectionHeader(
          group: group,
          count: 2,
          onAdd: () {},
          addTooltip: 'Add machine',
          onLoadSessions: () => loads++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(PhosphorIconsRegular.cloudArrowDown), findsOneWidget);
    await tester.tap(loadButton);
    await tester.pumpAndSettle();

    expect(loads, 1);
  });

  testWidgets('a run in flight turns the button into a stop', (tester) async {
    var loads = 0;
    var cancels = 0;
    await pumpTestApp(
      tester,
      Scaffold(
        body: GroupSectionHeader(
          group: group,
          count: 2,
          onAdd: () {},
          addTooltip: 'Add machine',
          onLoadSessions: () => loads++,
          onCancelLoadSessions: () => cancels++,
          isLoadingSessions: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(PhosphorIconsRegular.cloudArrowDown), findsNothing);
    expect(
      find.descendant(
        of: loadButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(loadButton);
    await tester.pump();

    expect(cancels, 1);
    expect(loads, 0);
  });
}

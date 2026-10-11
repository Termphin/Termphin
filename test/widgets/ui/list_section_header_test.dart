import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/widgets/ui/list_section_header.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('ListSectionHeader renders title and count badge', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Scaffold(body: ListSectionHeader(title: 'All machines', count: 5)),
    );
    await tester.pumpAndSettle();

    expect(find.text('All machines'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.byType(CountBadge), findsOneWidget);
  });

  testWidgets('ListSectionHeader triggers onAdd when add button is tapped', (
    tester,
  ) async {
    var added = false;
    await pumpTestApp(
      tester,
      Scaffold(
        body: ListSectionHeader(
          title: 'All snippets',
          count: 12,
          addTooltip: 'New snippet',
          onAdd: () => added = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All snippets'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    final addButton = find.byTooltip('New snippet');
    expect(addButton, findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.plus), findsOneWidget);

    await tester.tap(addButton);
    await tester.pump();
    expect(added, isTrue);
  });

  testWidgets('ListSectionHeader renders custom middle widget and actions', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      const Scaffold(
        body: ListSectionHeader(
          title: 'All keys',
          middle: Text('MiddleContent'),
          actions: [Text('Action1')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All keys'), findsOneWidget);
    expect(find.text('MiddleContent'), findsOneWidget);
    expect(find.text('Action1'), findsOneWidget);
  });

  testWidgets('ListSectionHeader.sliver works inside CustomScrollView', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: CustomScrollView(
          slivers: [ListSectionHeader.sliver(title: 'All machines', count: 3)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All machines'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}

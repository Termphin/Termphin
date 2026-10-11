import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/profiles/profile_card.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool isLoadingSessions,
    String? sessionsCheckedLabel,
    VoidCallback? onCancelLoadSessions,
  }) => pumpTestApp(
    tester,
    Scaffold(
      body: ProfileCard(
        profile: profileFixture(),
        onTap: () {},
        onEdit: () {},
        onLoadSessions: () {},
        onDelete: () {},
        onCancelLoadSessions: onCancelLoadSessions,
        isLoadingSessions: isLoadingSessions,
        sessionsCheckedLabel: sessionsCheckedLabel,
      ),
    ),
  );

  testWidgets('a fetch in flight is reported on the card itself', (
    tester,
  ) async {
    await pumpCard(tester, isLoadingSessions: true);

    expect(find.text('Loading sessions from the server…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'the fetch replaces the checked-at line rather than stacking on it',
    (tester) async {
      await pumpCard(
        tester,
        isLoadingSessions: true,
        sessionsCheckedLabel: 'Checked 3m ago',
      );

      expect(find.text('Checked 3m ago'), findsNothing);

      await pumpCard(
        tester,
        isLoadingSessions: false,
        sessionsCheckedLabel: 'Checked 3m ago',
      );

      expect(find.text('Checked 3m ago'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('the fetch in flight can be stopped from the card', (
    tester,
  ) async {
    var cancels = 0;
    await pumpCard(
      tester,
      isLoadingSessions: true,
      onCancelLoadSessions: () => cancels++,
    );

    await tester.tap(find.byKey(const ValueKey('cancelLoadSessions')));
    await tester.pump();

    expect(cancels, 1);
  });

  testWidgets('nothing in flight means no stop to press', (tester) async {
    await pumpCard(
      tester,
      isLoadingSessions: false,
      onCancelLoadSessions: () {},
    );

    expect(find.byKey(const ValueKey('cancelLoadSessions')), findsNothing);
  });
}

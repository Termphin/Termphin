import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/providers/live_presence_provider.dart';
import 'package:termphin/providers/sync_provider.dart';
import 'package:termphin/services/realtime/presence_state.dart';
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

  testWidgets('a server its agent reports for shows the online dot', (
    tester,
  ) async {
    Future<void> pumpWith(Map<String, ServerPresence> presence) {
      final container = ProviderContainer(
        overrides: [
          livePresenceProvider.overrideWith(() => _FixedPresence(presence)),
        ],
      );
      addTearDown(container.dispose);
      return pumpTestApp(
        tester,
        Scaffold(
          body: ProfileCard(
            profile: profileFixture(),
            onTap: () {},
            onEdit: () {},
            onLoadSessions: () {},
            onDelete: () {},
          ),
        ),
        container: container,
      );
    }

    final semantics = tester.ensureSemantics();
    final id = profileFixture().id;
    await pumpWith({
      id: ServerPresence(keyId: 'k', online: true, at: DateTime(2026)),
    });
    expect(find.byKey(const ValueKey('profileOnlineDot')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\bOnline\b')), findsOneWidget);

    await pumpWith({
      id: ServerPresence(keyId: 'k', online: false, at: DateTime(2026)),
    });
    expect(find.byKey(const ValueKey('profileOnlineDot')), findsNothing);

    await pumpWith(const {});
    expect(find.byKey(const ValueKey('profileOnlineDot')), findsNothing);
    semantics.dispose();
  });

  testWidgets('an online machine whose sessions this device cannot read yet '
      'says they are on their way while sync runs', (tester) async {
    final id = profileFixture().id;
    Future<void> pumpWith({
      required bool running,
      List<PresenceSession>? sessions,
    }) {
      final container = ProviderContainer(
        overrides: [
          livePresenceProvider.overrideWith(
            () => _FixedPresence({
              id: ServerPresence(
                keyId: 'k',
                online: true,
                at: DateTime(2026),
                sessions: sessions,
              ),
            }),
          ),
          syncRunningProvider.overrideWith(() => _Running(running)),
        ],
      );
      addTearDown(container.dispose);
      return pumpTestApp(
        tester,
        Scaffold(
          body: ProfileCard(
            profile: profileFixture(),
            onTap: () {},
            onEdit: () {},
            onLoadSessions: () {},
            onDelete: () {},
            onCancelLoadSessions: () {},
          ),
        ),
        container: container,
      );
    }

    await pumpWith(running: true);
    expect(find.text('Loading sessions from the server…'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancelLoadSessions')), findsNothing);

    await pumpWith(running: true, sessions: const []);
    expect(find.text('Loading sessions from the server…'), findsNothing);

    await pumpWith(running: false);
    expect(find.text('Loading sessions from the server…'), findsNothing);
  });
}

class _Running extends SyncRunningNotifier {
  _Running(this.value);

  final bool value;

  @override
  bool build() => value;
}

class _FixedPresence extends LivePresenceNotifier {
  _FixedPresence(this.value);

  final Map<String, ServerPresence> value;

  @override
  Map<String, ServerPresence> build() => value;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/providers/anonymize_provider.dart';
import 'package:termphin/providers/live_presence_provider.dart';
import 'package:termphin/services/realtime/presence_state.dart';
import 'package:termphin/widgets/terminal/session_activity_line.dart';

import '../../support/test_app.dart';

class _FixedPresence extends LivePresenceNotifier {
  _FixedPresence(this.value);

  final Map<String, ServerPresence> value;

  @override
  Map<String, ServerPresence> build() => value;
}

class _Anonymize extends AnonymizeNotifier {
  _Anonymize(this.value);

  final bool value;

  @override
  bool build() => value;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    SessionActivity? activity, {
    bool anonymize = false,
    bool restorable = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        livePresenceProvider.overrideWith(
          () => _FixedPresence({
            'profile-a': ServerPresence(
              keyId: 'k',
              online: true,
              at: DateTime(2026),
              sessions: [
                PresenceSession(
                  name: 'main',
                  createdAt: DateTime(2026),
                  clients: 0,
                  activity: activity,
                  restorable: restorable,
                ),
              ],
            ),
          }),
        ),
        anonymizeProvider.overrideWith(() => _Anonymize(anonymize)),
      ],
    );
    addTearDown(container.dispose);
    await pumpTestApp(
      tester,
      const Scaffold(
        body: SessionActivityLine(profileId: 'profile-a', muxName: 'main'),
      ),
      container: container,
    );
  }

  testWidgets('a working session names its program', (tester) async {
    await pump(
      tester,
      const SessionActivity(
        state: SessionActivityState.working,
        command: 'npm run build',
      ),
    );
    expect(find.text('npm run build · Working'), findsOneWidget);
  });

  testWidgets('a waiting session stands out', (tester) async {
    await pump(
      tester,
      const SessionActivity(
        state: SessionActivityState.waiting,
        command: 'claude',
      ),
    );
    final text = tester.widget<Text>(find.text('claude · Waiting for you'));
    expect(text.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('idle, unknown or unnamed', (tester) async {
    await pump(tester, const SessionActivity(state: SessionActivityState.idle));
    expect(find.byKey(const ValueKey('sessionActivity')), findsNothing);
    await pump(tester, null);
    expect(find.byKey(const ValueKey('sessionActivity')), findsNothing);
    await pump(
      tester,
      const SessionActivity(state: SessionActivityState.running),
    );
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('a session a reboot stopped says it restores', (tester) async {
    await pump(tester, null, restorable: true);
    expect(find.text('Restores when opened'), findsOneWidget);
  });

  testWidgets('anonymized, only the state shows', (tester) async {
    await pump(
      tester,
      const SessionActivity(
        state: SessionActivityState.working,
        command: 'ssh prod-db',
      ),
      anonymize: true,
    );
    expect(find.text('Working'), findsOneWidget);
    expect(find.textContaining('prod-db'), findsNothing);
  });
}

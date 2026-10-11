import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

/// Two tabs, "Production" then "Machine 2", with the second one showing.
Future<void> _openTwoTabs(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final profile = profileFixture();
  final second = profileFixture(
    id: 'profile-2',
    name: 'Machine 2',
    host: 'machine-2.example.com',
  );
  final backend = FakeSshBackend();
  final manager = SshSessionManager.test(
    remoteAgentService: FakeRemoteAgentService(backend)..supported = false,
    serviceFactory: backend.createService,
  );
  final container = ProviderContainer.test(
    overrides: [
      sshSessionManagerProvider.overrideWithValue(manager),
      profileStorageProvider.overrideWithValue(
        FakeProfileStorage([profile, second]),
      ),
    ],
  );
  addTearDown(manager.dispose);
  container.read(profilesProvider);
  await container.read(profilesProvider.notifier).loadProfiles();

  await pumpTestApp(
    tester,
    TerminalScreen(initialSessionId: 'session-1', initialProfile: profile),
    container: container,
  );
  await backend.connectCalled.future;
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('tabBarAddButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Machine 2'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Offstage pages included: the one not showing is exactly what is checked.
Finder _page(int index) =>
    find.byKey(ValueKey('sessionSwipePage-$index'), skipOffstage: false);

double _shift(WidgetTester tester, int index) =>
    tester.widget<Transform>(_page(index)).transform.getTranslation().x;

bool _shown(WidgetTester tester, int index) => !tester
    .widget<Offstage>(
      find
          .ancestor(
            of: _page(index),
            matching: find.byType(Offstage, skipOffstage: false),
          )
          .first,
    )
    .offstage;

FontWeight? _weight(WidgetTester tester, String name) =>
    tester.widget<Text>(find.text(name)).style?.fontWeight;

void main() {
  testWidgets('a tapped tab slides in from its side, pushing the other out', (
    tester,
  ) async {
    await _openTwoTabs(tester);
    final width = tester
        .getSize(find.byKey(const ValueKey('sessionSwipeArea')))
        .width;
    expect(_shown(tester, 0), isFalse);

    await tester.tap(find.text('Production'));
    await tester.pump();

    expect(_weight(tester, 'Production'), FontWeight.w600);
    expect(_shown(tester, 0), isTrue);
    expect(_shown(tester, 1), isTrue);
    expect(_shift(tester, 0), closeTo(-width, 0.5), reason: 'from the left');

    await tester.pump(const Duration(milliseconds: 90));
    final entering = _shift(tester, 0);
    expect(entering, inExclusiveRange(-width, 0));
    expect(_shift(tester, 1), closeTo(entering + width, 0.5));

    await tester.pump(const Duration(milliseconds: 300));
    expect(_shift(tester, 0), 0);
    expect(_shown(tester, 1), isFalse);
  });

  testWidgets('and the other way from the right', (tester) async {
    await _openTwoTabs(tester);
    await tester.tap(find.text('Production'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final width = tester
        .getSize(find.byKey(const ValueKey('sessionSwipeArea')))
        .width;

    await tester.tap(find.text('Machine 2'));
    await tester.pump();

    expect(_shift(tester, 1), closeTo(width, 0.5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_shift(tester, 1), 0);
    expect(_shown(tester, 0), isFalse);
  });

  testWidgets('the tab already showing does not slide', (tester) async {
    await _openTwoTabs(tester);

    await tester.tap(find.text('Machine 2'));
    await tester.pump();

    expect(_shift(tester, 1), 0);
    expect(_shown(tester, 0), isFalse);
  });

  testWidgets('no slide when the system asks for less motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _openTwoTabs(tester);

    await tester.tap(find.text('Production'));
    await tester.pump();

    expect(_weight(tester, 'Production'), FontWeight.w600);
    expect(_shift(tester, 0), 0);
    expect(_shown(tester, 1), isFalse);
  });

  testWidgets('the page takes no taps until it has landed', (tester) async {
    await _openTwoTabs(tester);

    await tester.tap(find.text('Production'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    bool ignored() => tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: _page(0),
                matching: find.byType(IgnorePointer, skipOffstage: false),
              )
              .first,
        )
        .ignoring;
    expect(ignored(), isTrue);

    await tester.pump(const Duration(milliseconds: 400));
    expect(ignored(), isFalse);
  });
}

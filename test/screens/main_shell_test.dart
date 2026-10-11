import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/screens/main_shell.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/settings/sidebar_settings.dart';
import 'package:termphin/services/settings/tab_bar_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/profiles/profile_avatar.dart';
import 'package:termphin/widgets/terminal/floating_action_dock.dart';
import 'package:termphin/widgets/ui/app_notifications.dart';
import 'package:termphin/widgets/ui/nav_rail.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/ssh_fakes.dart';
import '../support/test_app.dart';

/// The dock and the [TerminalScreen] it can open both read
/// `sshSessionManagerProvider` - fake it out so neither reaches out over the
/// network, and seed dock state on the same fake so the two agree.
(ProviderContainer, SshSessionManager) _containerWithFakeConnect() {
  final backend = FakeSshBackend();
  final manager = SshSessionManager.test(
    remoteAgentService: FakeRemoteAgentService(backend),
    serviceFactory: backend.createService,
  );
  final container = ProviderContainer.test(
    overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
  );
  return (container, manager);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'ready-to-restore dock re-attaches the dropped tab with sibling scope all',
    (tester) async {
      final profile = profileFixture();
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      final tabId = fakeManager.adoptRemoteSession(profile, 'devbox');
      await fakeManager.setActiveSession(tabId);

      await pumpTestApp(tester, const MainShell(), container: container);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text('Ready to restore · deploy@example.com'),
        findsOneWidget,
      );
      expect(find.byTooltip('Re-attach'), findsOneWidget);
      expect(container.read(terminalOverlayProvider), isNull);

      await tester.tap(find.byTooltip('Re-attach'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay, isNotNull);
      expect(overlay!.$1, tabId);
      expect(overlay.$2, profile);
      expect(overlay.$3, SiblingScope.all);
    },
  );

  testWidgets(
    'ready-to-restore dock always resolves to the most recently active dropped tab',
    (tester) async {
      final profileA = profileFixture(id: 'profile-a', name: 'Alpha');
      final profileB = profileFixture(
        id: 'profile-b',
        name: 'Bravo',
        host: 'bravo.example.com',
      );
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      final tabA = fakeManager.adoptRemoteSession(profileA, 'devbox-a');
      final tabB = fakeManager.adoptRemoteSession(profileB, 'devbox-b');
      await fakeManager.setActiveSession(tabA);
      await fakeManager.setActiveSession(tabB);

      await pumpTestApp(tester, const MainShell(), container: container);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);

      await tester.tap(find.byTooltip('Re-attach'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay!.$1, tabB);
      expect(overlay.$2, profileB);
      expect(overlay.$3, SiblingScope.all);
    },
  );

  /// The overlay provider only records the request; what the user actually
  /// waits for is the terminal coming to the front. Asserting the provider
  /// value - which the home screen's own tests already do - proves the tap was
  /// heard, not that anything appeared.
  double terminalOpacity(WidgetTester tester) {
    final finder = find.ancestor(
      of: find.byType(TerminalScreen),
      matching: find.byType(AnimatedOpacity),
    );
    if (finder.evaluate().isEmpty) return 0;
    return tester.widget<AnimatedOpacity>(finder.first).opacity;
  }

  testWidgets(
    'tapping a detached session row brings the terminal to the front',
    (tester) async {
      final profile = profileFixture();

      final backend = FakeSshBackend();
      final fakeManager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(backend),
        serviceFactory: backend.createService,
      );
      addTearDown(fakeManager.dispose);
      final tabId = fakeManager.adoptRemoteSession(profile, 'devbox');
      final container = ProviderContainer.test(
        overrides: [
          sshSessionManagerProvider.overrideWithValue(fakeManager),
          profileStorageProvider.overrideWithValue(
            FakeProfileStorage([profile]),
          ),
        ],
      );
      await container.read(profilesProvider.notifier).loadProfiles();

      await pumpTestApp(tester, const MainShell(), container: container);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(terminalOpacity(tester), 0);

      await tester.tap(find.text('devbox'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(terminalOverlayProvider)?.$1, tabId);
      expect(terminalOpacity(tester), 1.0);
    },
  );

  testWidgets('the same session row opens again after backing out of it', (
    tester,
  ) async {
    final profile = profileFixture();

    final backend = FakeSshBackend();
    final fakeManager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    addTearDown(fakeManager.dispose);
    fakeManager.adoptRemoteSession(profile, 'devbox');
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(fakeManager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('devbox'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 1.0);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 0);

    await tester.tap(find.text('devbox'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 1.0);
  });

  testWidgets('toasts hang from the top edge once the tabs are at the bottom', (
    tester,
  ) async {
    addTearDown(() => tabBarPositionSetting.set(TabBarPosition.top));
    final profile = profileFixture();

    final backend = FakeSshBackend();
    final fakeManager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    addTearDown(fakeManager.dispose);
    fakeManager.adoptRemoteSession(profile, 'devbox');
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(fakeManager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('devbox'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final strip = terminalTabBarHeight(tester.element(find.byType(MainShell)));
    expect(appNotificationAnchor.value, strip);

    await tabBarPositionSetting.set(TabBarPosition.bottom);
    expect(appNotificationAnchor.value, 0, reason: 'nothing up top now');

    await tabBarPositionSetting.set(TabBarPosition.top);
    expect(appNotificationAnchor.value, strip);
  });

  testWidgets('system back closes the action dock before the terminal', (
    tester,
  ) async {
    final profile = profileFixture();

    final backend = FakeSshBackend();
    final fakeManager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    addTearDown(fakeManager.dispose);
    fakeManager.adoptRemoteSession(profile, 'devbox');
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(fakeManager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('devbox'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 1.0);

    await tester.tap(
      find
          .descendant(
            of: find.byType(FloatingActionDock),
            matching: find.byType(Icon),
          )
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paste'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paste'), findsNothing);
    expect(terminalOpacity(tester), 1.0);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 0);
  });

  testWidgets('an unselected nav item fades out its own colour, not black', (
    tester,
  ) async {
    final (container, fakeManager) = _containerWithFakeConnect();
    addTearDown(fakeManager.dispose);
    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final fills = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const ValueKey('bottomNavBar')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((c) => (c.decoration! as BoxDecoration).color!)
        .toList();

    final highlight = AppColors.dark.primaryHighlight;
    expect(fills, contains(highlight));
    final unselected = fills.where((c) => c != highlight);
    expect(unselected, isNotEmpty);
    for (final fill in unselected) {
      expect(fill.a, 0);
      expect(fill.r, highlight.r);
      expect(fill.g, highlight.g);
      expect(fill.b, highlight.b);
    }
  });

  group('the wide-layout sidebar collapses', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await sidebarCollapsedSetting.load();
    });
    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await sidebarCollapsedSetting.load();
    });

    Finder inSidebar(Finder matching) => find.descendant(
      of: find.byKey(const ValueKey('sidebarNav')),
      matching: matching,
    );

    testWidgets('behind a landscape cutout, which it grows by rather than '
        'losing its icons to', (tester) async {
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      await pumpTestApp(tester, const MainShell(), container: container);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.padding = const FakeViewPadding(left: 48);
      tester.view.viewPadding = const FakeViewPadding(left: 48);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.getSize(find.byKey(const ValueKey('sidebarNav'))).width,
        kNavRailCollapsedWidth + 48,
      );
      final home = tester.getRect(inSidebar(find.byTooltip('Home')));
      expect(home.width, greaterThan(40));
      expect(home.left, greaterThanOrEqualTo(48));
    });

    testWidgets('the hamburger drops the labels and narrows the rail', (
      tester,
    ) async {
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      await pumpTestApp(tester, const MainShell(), container: container);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      double railWidth() =>
          tester.getSize(find.byKey(const ValueKey('sidebarNav'))).width;

      expect(railWidth(), kNavRailWidth);
      expect(inSidebar(find.text('Snippets')), findsOneWidget);

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(railWidth(), kNavRailCollapsedWidth);
      expect(inSidebar(find.text('Snippets')), findsNothing);
      expect(inSidebar(find.byTooltip('Snippets')), findsOneWidget);
      expect(find.byTooltip('Expand sidebar'), findsOneWidget);

      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(railWidth(), kNavRailWidth);
      expect(inSidebar(find.text('Snippets')), findsOneWidget);
    });

    testWidgets('a collapsed rail still switches tabs, and is remembered', (
      tester,
    ) async {
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      await pumpTestApp(tester, const MainShell(), container: container);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(sidebarCollapsedSetting.value, isTrue);
      await sidebarCollapsedSetting.load();
      expect(sidebarCollapsedSetting.value, isTrue);

      await tester.tap(inSidebar(find.byTooltip('Keys')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('SSH Keys'), findsWidgets);
    });

    testWidgets('the session dock keeps its avatar when collapsed', (
      tester,
    ) async {
      final profile = profileFixture();
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      final tabId = fakeManager.adoptRemoteSession(profile, 'devbox');
      await fakeManager.setActiveSession(tabId);

      await pumpTestApp(tester, const MainShell(), container: container);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        inSidebar(find.text('Ready to restore · deploy@example.com')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        inSidebar(find.text('Ready to restore · deploy@example.com')),
        findsNothing,
      );
      expect(inSidebar(find.byType(ProfileAvatar)), findsOneWidget);
      expect(find.byTooltip('Re-attach'), findsOneWidget);
    });
  });
}

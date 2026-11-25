import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/screens/main_shell.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/app/app_commands.dart';
import 'package:termphin/services/settings/sidebar_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/profiles/profile_avatar.dart';
import 'package:termphin/widgets/shell/nav_rail.dart';
import 'package:termphin/widgets/terminal/add_session_sheet.dart';
import 'package:termphin/widgets/terminal/floating_action_dock.dart';
import 'package:termphin/widgets/ui/fade_over_color.dart';

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
  final t = AppLocale.en.buildSync();
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
      matching: find.byType(FadeOverColor),
    );
    if (finder.evaluate().isEmpty) return 0;
    return tester.widget<FadeOverColor>(finder.first).opacity;
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(terminalOverlayProvider)?.$1, tabId);
      expect(terminalOpacity(tester), 1.0);
    },
  );

  testWidgets('a new session asked for off the terminal opens the same '
      'machine picker the terminal does', (tester) async {
    final (container, fakeManager) = _containerWithFakeConnect();
    addTearDown(fakeManager.dispose);
    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(AppCommands.instance.run(AppCommand.newSession), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AddSessionSheetContent), findsOneWidget);
    expect(find.byType(GlobalSearchScreen), findsNothing);
  });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 1.0);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 0);

    await tester.tap(find.text('devbox'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(terminalOpacity(tester), 1.0);
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

  testWidgets('the open tab sits on the bar\'s one lighter segment', (
    tester,
  ) async {
    final (container, fakeManager) = _containerWithFakeConnect();
    addTearDown(fakeManager.dispose);
    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final bar = find.byKey(const ValueKey('bottomNavBar'));
    final segments = find.descendant(
      of: bar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration).color ==
                AppColors.dark.surfaceOffset2,
      ),
    );
    expect(segments, findsOneWidget);
    final segment = tester.getRect(segments);
    final home = tester.getCenter(
      find.descendant(of: bar, matching: find.text(t.nav.home)),
    );
    expect(segment.contains(home), isTrue);
  });

  testWidgets('dock badge tracks the mounted strip count after minimizing', (
    tester,
  ) async {
    final profile = profileFixture();
    final (container, fakeManager) = _containerWithFakeConnect();
    addTearDown(fakeManager.dispose);

    await pumpTestApp(tester, const MainShell(), container: container);
    await tester.pump();
    await fakeManager.startSession(profile, sessionId: 'tab-1');
    await fakeManager.startSession(profile, sessionId: 'tab-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final navBar = find.byKey(const ValueKey('bottomNavBar'));
    expect(
      find.descendant(of: navBar, matching: find.text('2')),
      findsOneWidget,
    );

    container
        .read(terminalOverlayProvider.notifier)
        .show('tab-2', profile, scope: SiblingScope.none);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.descendant(of: navBar, matching: find.text('2')), findsNothing);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(railWidth(), kNavRailCollapsedWidth);
      expect(inSidebar(find.text('Snippets')), findsNothing);
      expect(inSidebar(find.byTooltip('Snippets')), findsOneWidget);
      expect(find.byTooltip('Expand sidebar'), findsOneWidget);

      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(railWidth(), kNavRailWidth);
      expect(inSidebar(find.text('Snippets')), findsOneWidget);
    });

    testWidgets('a phone on its side gets the same rail as a tablet', (
      tester,
    ) async {
      final (container, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      await pumpTestApp(tester, const MainShell(), container: container);
      tester.view.physicalSize = const Size(844, 390);
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
      expect(find.byTooltip('Expand sidebar'), findsOneWidget);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(sidebarCollapsedSetting.value, isTrue);
      await sidebarCollapsedSetting.load();
      expect(sidebarCollapsedSetting.value, isTrue);

      await tester.tap(inSidebar(find.byTooltip('Keys')));
      await tester.pump();
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

  testWidgets(
    'mobile bottom bar docks at top and lifts into a floating pill with labels on scroll',
    (tester) async {
      final profiles = [
        for (var i = 0; i < 16; i++)
          profileFixture(
            id: 'p-$i',
            name: 'Server $i',
            host: 'srv$i.example.com',
          ),
      ];
      final (_, fakeManager) = _containerWithFakeConnect();
      addTearDown(fakeManager.dispose);
      final testContainer = ProviderContainer.test(
        overrides: [
          sshSessionManagerProvider.overrideWithValue(fakeManager),
          profileStorageProvider.overrideWithValue(
            FakeProfileStorage(profiles),
          ),
        ],
      );
      await testContainer.read(profilesProvider.notifier).loadProfiles();

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpTestApp(tester, const MainShell(), container: testContainer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final navBar = find.byKey(const ValueKey('bottomNavBar'));
      final dockedMargin = tester
          .widget<AnimatedPadding>(
            find
                .descendant(of: navBar, matching: find.byType(AnimatedPadding))
                .first,
          )
          .padding;
      expect(dockedMargin, EdgeInsets.zero);
      expect(
        find.descendant(of: navBar, matching: find.text(t.nav.home)),
        findsOneWidget,
      );

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      final floatMargin =
          tester
                  .widget<AnimatedPadding>(
                    find
                        .descendant(
                          of: navBar,
                          matching: find.byType(AnimatedPadding),
                        )
                        .first,
                  )
                  .padding
              as EdgeInsets;
      final floatOuter = tester.widget<AnimatedContainer>(
        find
            .descendant(of: navBar, matching: find.byType(AnimatedContainer))
            .first,
      );
      expect(floatOuter.padding, isNull);
      expect(floatMargin.left, AppTheme.space16);
      expect(
        find.descendant(of: navBar, matching: find.text(t.nav.home)),
        findsOneWidget,
      );

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      final redockedMargin = tester
          .widget<AnimatedPadding>(
            find
                .descendant(of: navBar, matching: find.byType(AnimatedPadding))
                .first,
          )
          .padding;
      expect(redockedMargin, EdgeInsets.zero);
    },
  );
}

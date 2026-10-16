import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/snippets_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/sidebar_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/profiles/profile_avatar.dart';
import 'package:termphin/widgets/shell/nav_rail.dart';
import 'package:termphin/widgets/terminal/floating_action_dock.dart';
import 'package:termphin/widgets/terminal/special_keys_toolbar.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';
import 'package:termphin/widgets/ui/fade_over_color.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

/// The keyboard takes its room straight from the Scaffold's body height, with
/// no stored inset to go stale once the keyboard is gone - the pane just
/// follows whatever height the frame gives it, which is also why the resize
/// must be debounced to one window-change per animation rather than one per
/// frame: a full-screen TUI would otherwise repaint for each intermediate
/// height.
void main() {
  testWidgets('navigates sessions and exposes modes below the tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final profiles = [
      profile,
      for (var i = 2; i <= 5; i++)
        profileFixture(
          id: 'profile-$i',
          name: 'Machine $i',
          host: 'machine-$i.example.com',
        ),
    ];
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend)..supported = false,
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage(profiles)),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();

    var hidden = false;
    await pumpTestApp(
      tester,
      TerminalScreen(
        initialSessionId: 'session-1',
        initialProfile: profile,
        onHide: () => hidden = true,
      ),
      container: container,
    );
    await backend.connectCalled.future;
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, 58);
    expect(appBar.bottom, isNull);
    expect(appBar.leading, isNull);
    expect(find.byType(ProfileAvatar), findsOneWidget);
    for (final key in const [
      'tabBarBackButton',
      'tabBarQuickSettingsButton',
      'tabBarAddButton',
    ]) {
      final button = tester.widget<Material>(find.byKey(ValueKey(key)));
      expect(button.color, AppColors.dark.surfaceOffset);
    }
    final dividers = find.descendant(
      of: find.byType(AppBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints ==
                const BoxConstraints.tightFor(width: 1, height: 24),
      ),
    );
    expect(dividers, findsNothing);
    final statusAvatar = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('sessionStatusAvatar-session-1')),
    );
    final statusDecoration = statusAvatar.decoration! as BoxDecoration;
    expect(
      (statusDecoration.border! as Border).top.color,
      AppColors.dark.success,
    );

    final back = find.byIcon(PhosphorIconsFill.arrowLeft);
    final plus = find.byIcon(PhosphorIconsRegular.plus);
    expect(back, findsOneWidget);
    expect(plus, findsOneWidget);
    expect(tester.getCenter(back).dx, lessThan(tester.getCenter(plus).dx));
    final modeBadge = find.byKey(const ValueKey('viewModeBadge-session-1'));
    expect(
      find.descendant(
        of: modeBadge,
        matching: find.byIcon(PhosphorIconsFill.terminalWindow),
      ),
      findsOneWidget,
    );
    final tabMenu = find.descendant(
      of: find.byKey(const ValueKey('sessionTabContent-session-1')),
      matching: find.byIcon(PhosphorIconsRegular.dotsThreeVertical),
    );
    await tester.tap(tabMenu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Connection log'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('viewModeSegment-session-1-sftp')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Connection log'), findsNothing);
    expect(
      find.descendant(
        of: modeBadge,
        matching: find.byIcon(PhosphorIconsFill.folderOpen),
      ),
      findsOneWidget,
    );

    await tester.tap(tabMenu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const ValueKey('viewModeSegment-session-1-terminal')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    for (final additionalProfile in profiles.skip(1)) {
      await tester.tap(plus);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final profileChoice = find.byKey(
        ValueKey('addSessionProfile:${additionalProfile.id}'),
      );
      await tester.scrollUntilVisible(
        profileChoice,
        160,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('addSessionProfileList')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(profileChoice);
      await tester.pump();
      await tester.tap(profileChoice);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.pump(const Duration(milliseconds: 300));
    final tabViewport = tester.getRect(
      find.byKey(const ValueKey('sessionTabScroll')),
    );
    final lastTab = tester.getRect(find.text('Machine 5'));
    expect(lastTab.left, greaterThanOrEqualTo(tabViewport.left));
    expect(lastTab.right, lessThanOrEqualTo(tabViewport.right));
    expect(
      tester.widget<Text>(find.text('Machine 5')).style?.fontWeight,
      FontWeight.w600,
    );

    final swipeArea = find.byKey(const ValueKey('sessionSwipeArea'));
    final swipe = await tester.startGesture(tester.getCenter(swipeArea));
    await swipe.moveBy(const Offset(120, 0));
    await tester.pump();
    final activePage = tester.widget<Transform>(
      find.byKey(const ValueKey('sessionSwipePage-4')),
    );
    expect(activePage.transform.getTranslation().x, closeTo(120, 0.1));
    await swipe.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<Text>(find.text('Machine 4')).style?.fontWeight,
      FontWeight.w600,
    );

    await tester.drag(swipeArea, const Offset(-120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<Text>(find.text('Machine 5')).style?.fontWeight,
      FontWeight.w600,
    );

    await tester.tap(back);
    expect(hidden, isTrue);
  });

  testWidgets('the tab strip grows with the system font scale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend)..supported = false,
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: TerminalScreen(
          initialSessionId: 'session-1',
          initialProfile: profile,
        ),
      ),
      container: container,
    );
    await backend.connectCalled.future;
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, greaterThanOrEqualTo(58));

    final pill = tester.getRect(
      find.byKey(const ValueKey('sessionTabContent-session-1')),
    );
    final label = tester.getRect(find.text(profile.name));
    expect(label.top, greaterThanOrEqualTo(pill.top));
    expect(label.bottom, lessThanOrEqualTo(pill.bottom));
  });

  group('a tab is reordered by dragging it', () {
    /// The pills in the order they are laid out, top-left first - which is
    /// left to right in the strip and top to bottom in the rail.
    List<String> tabOrder(WidgetTester tester) {
      final placed = <String, double>{};
      for (final element
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'sessionTabContent-',
                    ),
              )
              .evaluate()) {
        final key = element.widget.key! as ValueKey<String>;
        final rect = tester.getRect(find.byKey(key));
        placed[key.value] = rect.top * 10000 + rect.left;
      }
      final entries = placed.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      return [for (final entry in entries) entry.key];
    }

    /// Press and hold, then move - the strip and the rail both start their
    /// drag off a long press, so a plain drag only scrolls them.
    Future<void> dragTab(WidgetTester tester, String key, Offset by) async {
      final start = tester.getCenter(find.byKey(ValueKey(key)));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var step = 1; step <= 8; step++) {
        await gesture.moveTo(start + by * (step / 8));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> openTwoTabs(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final profile = profileFixture();
      final second = profileFixture(
        id: 'profile-2',
        name: 'Machine 2',
        host: 'machine-2.example.com',
      );
      final backend = FakeSshBackend();
      final manager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(backend),
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

    testWidgets('sideways along the portrait strip', (tester) async {
      await openTwoTabs(tester);
      final before = tabOrder(tester);
      expect(before, hasLength(2));

      await dragTab(tester, before.first, const Offset(260, 0));

      expect(tabOrder(tester), before.reversed.toList());
    });

    testWidgets('and down a rail collapsed to avatars, where the tooltip is '
        'the only other thing a long press could mean', (tester) async {
      await openTwoTabs(tester);
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      addTearDown(() async {
        SharedPreferences.setMockInitialValues({});
        await sidebarCollapsedSetting.load();
      });

      final before = tabOrder(tester);
      expect(before, hasLength(2));

      await dragTab(tester, before.first, const Offset(0, 120));

      expect(tabOrder(tester), before.reversed.toList());
    });

    testWidgets('and down the landscape rail, which is the same list stood '
        'on its side', (tester) async {
      await openTwoTabs(tester);
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final before = tabOrder(tester);
      expect(before, hasLength(2));

      await dragTab(tester, before.first, const Offset(0, 120));

      expect(tabOrder(tester), before.reversed.toList());
    });
  });

  testWidgets('a toolbar snippet with arguments asks for them, then runs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferences.resetStatic();
      await loadAppSettings();
    });
    final snippet = Snippet(
      id: 'greet',
      name: 'Greet',
      command: 'echo hello {{who}}',
      createdAt: DateTime(2026, 9, 24),
    );
    await saveToolbarLayout(
      ToolbarLayout(
        order: [
          toolbarSnippetActionId(snippet.id),
          ...List.filled(kToolbarSlotCount - 1, ''),
        ],
      ),
    );

    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
        snippetStorageProvider.overrideWithValue(FakeSnippetStorage([snippet])),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();
    await container.read(snippetsProvider.notifier).loadSnippets();

    await pumpTestApp(
      tester,
      TerminalScreen(initialSessionId: 'session-1', initialProfile: profile),
      container: container,
    );
    await backend.connectCalled.future;
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    await tester.tap(
      find.descendant(
        of: find.byType(SpecialKeysToolbar),
        matching: find.text('Greet'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('snippetArgField:who')),
      'world',
    );
    await tester.tap(find.byKey(const ValueKey('snippetArgsRun')));
    await tester.pumpAndSettle();

    final typed = [
      for (final call in backend.calls)
        if (call.method == 'write')
          String.fromCharCodes((call.arguments as Map)['data'] as List<int>),
    ].join();
    expect(typed, contains('echo hello world'));
  });

  testWidgets('back closes an open action dock before anything else', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();

    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();

    final screenKey = GlobalKey<TerminalScreenState>();
    await pumpTestApp(
      tester,
      TerminalScreen(
        key: screenKey,
        initialSessionId: 'session-1',
        initialProfile: profile,
      ),
      container: container,
    );
    await backend.connectCalled.future;
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

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

    expect(screenKey.currentState!.handleBack(), isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paste'), findsNothing);

    expect(screenKey.currentState!.handleBack(), isFalse);
  });

  testWidgets('the key toolbar can be switched off without taking the dock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferences.resetStatic();
      await loadAppSettings();
    });

    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
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
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.byType(SpecialKeysToolbar), findsOneWidget);
    expect(find.byType(FloatingActionDock), findsOneWidget);

    await toolbarSettings.enabled.set(false);
    await tester.pump();

    expect(find.byType(SpecialKeysToolbar), findsNothing);
    expect(find.byType(FloatingActionDock), findsOneWidget);

    await toolbarSettings.enabled.set(true);
    await tester.pump();
    expect(find.byType(SpecialKeysToolbar), findsOneWidget);
  });

  testWidgets('a reconnect leaves the toolbar and the dock in place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferences.resetStatic();
      await loadAppSettings();
    });

    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
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
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.byType(SpecialKeysToolbar), findsOneWidget);

    backend.connectGate = Completer<void>();
    manager.markSessionDropped('session-1');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.byType(SpecialKeysToolbar), findsOneWidget);
    expect(find.byType(FloatingActionDock), findsOneWidget);

    backend.connectGate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  });

  testWidgets(
    'a newly opened tab is scrolled into view however wide the tabs are',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final profile = profileFixture(name: 'A very long machine name 1');
      final profiles = [
        profile,
        for (var i = 2; i <= 5; i++)
          profileFixture(
            id: 'profile-$i',
            name: 'A very long machine name $i',
            host: 'machine-$i.example.com',
          ),
      ];
      final backend = FakeSshBackend();
      final manager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(backend),
        serviceFactory: backend.createService,
      );
      final container = ProviderContainer.test(
        overrides: [
          sshSessionManagerProvider.overrideWithValue(manager),
          profileStorageProvider.overrideWithValue(
            FakeProfileStorage(profiles),
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
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      final plus = find.byIcon(PhosphorIconsRegular.plus);
      for (final additionalProfile in profiles.skip(1)) {
        await tester.tap(plus);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final choice = find.byKey(
          ValueKey('addSessionProfile:${additionalProfile.id}'),
        );
        await tester.scrollUntilVisible(
          choice,
          160,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('addSessionProfileList')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.ensureVisible(choice);
        await tester.pump();
        await tester.tap(choice);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      }

      final viewport = tester.getRect(
        find.byKey(const ValueKey('sessionTabScroll')),
      );
      final lastPill = tester.getRect(
        find.ancestor(
          of: find.textContaining('A very long machine name 5'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'sessionTabContent-',
                ),
          ),
        ),
      );

      expect(lastPill.left, greaterThanOrEqualTo(viewport.left - 0.5));
      expect(lastPill.right, lessThanOrEqualTo(viewport.right + 0.5));
    },
  );

  testWidgets('the landscape tab rail collapses to avatars', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await sidebarCollapsedSetting.load();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await sidebarCollapsedSetting.load();
    });

    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend)..supported = false,
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
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
    tester.view.physicalSize = const Size(1200, 800);
    await backend.connectCalled.future;
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    double railWidth() =>
        tester.getSize(find.byKey(const ValueKey('sessionTabScroll'))).width;

    expect(find.byType(AppBar), findsNothing);
    expect(railWidth(), closeTo(kNavRailWidth, 1));
    expect(find.text(profile.name), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse sidebar'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(railWidth(), closeTo(kNavRailCollapsedWidth, 1));
    expect(find.text(profile.name), findsNothing);
    expect(
      find.byKey(const ValueKey('sessionStatusAvatar-session-1')),
      findsOneWidget,
    );
    expect(find.byTooltip(profile.name), findsOneWidget);

    final toggle = tester.getRect(find.byTooltip('Expand sidebar'));
    final back = tester.getRect(find.byKey(const ValueKey('tabBarBackButton')));
    expect(back.top, greaterThanOrEqualTo(toggle.bottom - 0.5));
    expect(find.byKey(const ValueKey('tabBarAddButton')), findsOneWidget);
    final quick = tester.getRect(
      find.byKey(const ValueKey('tabBarQuickSettingsButton')),
    );
    final add = tester.getRect(find.byKey(const ValueKey('tabBarAddButton')));
    expect(add.top, greaterThanOrEqualTo(quick.bottom - 0.5));
  });

  testWidgets('a tapped tab crosses the old page along the X axis', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final second = profileFixture(
      id: 'profile-2',
      name: 'Machine 2',
      host: 'machine-2.example.com',
    );
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
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

    double opacityOf(int index) => tester
        .widget<FadeOverColor>(
          find
              .descendant(
                of: find.byKey(ValueKey('sessionSwipePage-$index')),
                matching: find.byType(FadeOverColor),
              )
              .first,
        )
        .opacity;
    double shiftOf(int index) => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byKey(ValueKey('sessionSwipePage-$index')),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .x;

    await tester.tap(find.byKey(const ValueKey('sessionTabItem-session-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacityOf(1), lessThan(1));
    expect(shiftOf(1), greaterThan(0));

    await tester.pump(const Duration(milliseconds: 120));
    expect(opacityOf(0), lessThan(1));
    expect(shiftOf(0), lessThan(0));
    expect(shiftOf(0), greaterThan(-31));

    await tester.pump(const Duration(milliseconds: 300));
    expect(opacityOf(0), 1);
    expect(shiftOf(0), 0);
  });

  testWidgets('a swiped tab stays off the landscape rail', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await sidebarCollapsedSetting.load();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await sidebarCollapsedSetting.load();
    });
    addTearDown(tester.view.resetPhysicalSize);

    final profile = profileFixture();
    final second = profileFixture(
      id: 'profile-2',
      name: 'Machine 2',
      host: 'machine-2.example.com',
    );
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
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
    tester.view.physicalSize = const Size(1200, 800);
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

    final swipeArea = find.byKey(const ValueKey('sessionSwipeArea'));
    final contentLeft = tester.getRect(swipeArea).left;
    final swipe = await tester.startGesture(tester.getCenter(swipeArea));
    await swipe.moveBy(const Offset(120, 0));
    await tester.pump();

    final page = find.byKey(const ValueKey('sessionSwipePage-1'));
    expect(
      tester.widget<Transform>(page).transform.getTranslation().x,
      closeTo(120, 0.1),
    );

    final clip = find.ancestor(of: page, matching: find.byType(ClipRect));
    expect(clip, findsWidgets);
    expect(tester.getRect(clip.first).left, greaterThanOrEqualTo(contentLeft));

    await swipe.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a first connect that fails keeps its tab and says why', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final backend = FakeSshBackend()
      ..connectError = Exception('No route to host');
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();

    var closed = false;
    await pumpTestApp(
      tester,
      TerminalScreen(
        initialSessionId: 'session-1',
        initialProfile: profile,
        onClose: () => closed = true,
      ),
      container: container,
    );
    await backend.connectCalled.future;
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(closed, isFalse);
    expect(find.text('Failed to connect.'), findsOneWidget);
    expect(find.textContaining('No route to host'), findsOneWidget);
  });

  testWidgets('resets keyboard inset on pause and syncs on resume', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    addTearDown(manager.dispose);
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();

    final screenKey = GlobalKey<TerminalScreenState>();
    await pumpTestApp(
      tester,
      TerminalScreen(
        key: screenKey,
        initialSessionId: 'session-1',
        initialProfile: profile,
      ),
      container: container,
    );
    await backend.connectCalled.future;
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    tester.view.viewInsets = FakeViewPadding.zero;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(SpecialKeysToolbar), findsOneWidget);
  });

  testWidgets('the keyboard takes room from the pane, never leaves it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
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
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final toolbar = find.byType(SpecialKeysToolbar);
    final pane = find.byType(TerminalPane).first;
    final restingBottom = tester.getRect(toolbar).bottom;
    final restingPaneHeight = tester.getRect(pane).height;
    expect(restingBottom, closeTo(screenHeight, 8));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.getRect(toolbar).bottom, closeTo(screenHeight - 300, 8));
    expect(tester.getRect(pane).height, closeTo(restingPaneHeight - 300, 8));

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(tester.getRect(toolbar).bottom, closeTo(restingBottom, 8));
    expect(tester.getRect(pane).height, closeTo(restingPaneHeight, 8));
  });

  testWidgets('one window-change per keyboard animation, not one per frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = profileFixture();
    final backend = FakeSshBackend();
    final manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
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
    await tester.pumpAndSettle();
    addTearDown(tester.view.resetViewInsets);

    backend.calls.clear();
    for (var inset = 60.0; inset <= 300.0; inset += 60) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    final resizes = backend.calls.where((call) => call.method == 'resize');
    expect(resizes, hasLength(1));
  });
}

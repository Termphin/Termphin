import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/floating_dock_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/terminal/floating_action_dock.dart';
import 'package:termphin/widgets/terminal/special_keys_toolbar.dart';
import 'package:termphin/widgets/ui/nav_rail.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

const _navItems = [
  ShellNavItem(
    label: 'Home',
    icon: PhosphorIconsRegular.terminal,
    selectedIcon: PhosphorIconsFill.terminal,
  ),
  ShellNavItem(
    label: 'Settings',
    icon: PhosphorIconsRegular.gearSix,
    selectedIcon: PhosphorIconsFill.gearSix,
  ),
];

/// One connected session, on a desktop-sized window, with the app's
/// destinations handed to the strip as `MainShell` hands them.
Future<List<int>> _pumpDesktopScreen(WidgetTester tester) async {
  final navigated = <int>[];
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
    TerminalScreen(
      initialSessionId: 'session-1',
      initialProfile: profile,
      navItems: _navItems,
      onNavigate: navigated.add,
    ),
    container: container,
  );
  tester.view.physicalSize = const Size(1400, 900);
  await backend.connectCalled.future;
  await tester.pumpAndSettle();
  return navigated;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  testWidgets('the rail is the app sidebar: destinations instead of a back '
      'arrow, sessions under them', (tester) async {
    final navigated = await _pumpDesktopScreen(tester);

    expect(find.byKey(const ValueKey('tabBarBackButton')), findsNothing);
    expect(find.byType(SidebarNavItem), findsNWidgets(_navItems.length));
    expect(find.byKey(const ValueKey('sessionTabScroll')), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(navigated, [1]);
  }, variant: _linux);

  testWidgets('the key toolbar and the floating dock stay off a desktop', (
    tester,
  ) async {
    await _pumpDesktopScreen(tester);

    expect(find.byType(SpecialKeysToolbar), findsNothing);
    expect(find.byType(FloatingActionDock), findsNothing);
  }, variant: _linux);

  testWidgets('the dock is a toolbar over the terminal, on its own '
      'switch', (tester) async {
    await _pumpDesktopScreen(tester);

    final bar = find.byKey(const ValueKey('desktopActionBar'));
    expect(bar, findsOneWidget);
    expect(find.byKey(const ValueKey('actionBar-search')), findsOneWidget);
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(bar);
    final rail = tester.getRect(find.byKey(const ValueKey('sessionTabScroll')));
    expect(rect.left, greaterThanOrEqualTo(rail.right));
    expect(rect.right, window.width);
    final first = tester.getRect(
      find.byKey(const ValueKey('actionBar-insertSnippet')),
    );
    expect(first.left, lessThan(rect.left + 16));
    expect(find.text('Search (Ctrl+Shift+F)'), findsOneWidget);
    expect(find.text('Fast upload (Ctrl+Shift+O)'), findsOneWidget);

    await floatingDockSettings.enabled.set(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktopActionBar')), findsNothing);
  }, variant: _linux);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/tab_bar_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/shell/nav_rail.dart';
import 'package:termphin/widgets/terminal/special_keys_toolbar.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

final _bar = find.byKey(const ValueKey('terminalTabBar'));
final _toolbar = find.byType(SpecialKeysToolbar);
Finder get _pane => find.byType(TerminalPane).first;

double _screenHeight(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio;

/// One connected session on a [TerminalScreen], tabs where [position] says.
Future<void> _pumpScreen(
  WidgetTester tester, {
  TabBarPosition position = TabBarPosition.bottom,
}) async {
  await tabBarPositionSetting.set(position);
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
}

Future<void> _switchToSftp(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('sessionTabContent-session-1')),
      matching: find.byIcon(PhosphorIconsRegular.dotsThreeVertical),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(
    find.byKey(const ValueKey('viewModeSegment-session-1-sftp')),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  testWidgets('tabs stay on top unless moved', (tester) async {
    await _pumpScreen(tester, position: TabBarPosition.top);

    expect(find.byType(AppBar), findsOneWidget);
    expect(
      tester.getRect(_bar).bottom,
      lessThanOrEqualTo(tester.getRect(_pane).top),
    );
  });

  testWidgets('at the bottom they sit between the terminal and the keys', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.byType(AppBar), findsNothing);
    final pane = tester.getRect(_pane);
    final bar = tester.getRect(_bar);
    final toolbar = tester.getRect(_toolbar);
    expect(pane.bottom, lessThanOrEqualTo(bar.top));
    expect(bar.bottom, lessThanOrEqualTo(toolbar.top));
    expect(
      toolbar.top - bar.bottom,
      lessThanOrEqualTo(1),
      reason: "nothing between but the toolbar's own edge line",
    );
    expect(toolbar.bottom, closeTo(_screenHeight(tester), 8));
  });

  testWidgets('its edge line faces the terminal, not a doubled one', (
    tester,
  ) async {
    await _pumpScreen(tester);

    final border =
        (tester.widget<Container>(_bar).decoration! as BoxDecoration).border!
            as Border;
    expect(border.top.style, BorderStyle.solid);
    expect(border.bottom, BorderSide.none);
  });

  testWidgets('moving the strip never resizes the terminal', (tester) async {
    await _pumpScreen(tester, position: TabBarPosition.top);
    final onTop = tester.getRect(_pane);

    await tabBarPositionSetting.set(TabBarPosition.bottom);
    await tester.pumpAndSettle();
    final atBottom = tester.getRect(_pane);

    expect(atBottom.size, onTop.size);
    expect(atBottom.top, lessThan(onTop.top), reason: 'the room moved up');

    await tabBarPositionSetting.set(TabBarPosition.top);
    await tester.pumpAndSettle();
    expect(tester.getRect(_pane), onTop);
  });

  testWidgets('with no keys it drops to the bottom edge', (tester) async {
    await _pumpScreen(tester);

    await toolbarSettings.enabled.set(false);
    await tester.pumpAndSettle();

    expect(_toolbar, findsNothing);
    expect(tester.getRect(_bar).bottom, closeTo(_screenHeight(tester), 8));
  });

  testWidgets('in the file browser it is the bottom row', (tester) async {
    await _pumpScreen(tester);

    await _switchToSftp(tester);

    expect(_toolbar, findsNothing);
    expect(tester.getRect(_bar).bottom, closeTo(_screenHeight(tester), 8));
  });

  testWidgets('the keyboard lifts it with the keys, still touching', (
    tester,
  ) async {
    await _pumpScreen(tester);
    final restingPane = tester.getRect(_pane).height;

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final screen = _screenHeight(tester);
    expect(tester.getRect(_toolbar).bottom, closeTo(screen - 300, 8));
    expect(
      tester.getRect(_toolbar).top - tester.getRect(_bar).bottom,
      lessThanOrEqualTo(1),
    );
    expect(tester.getRect(_pane).height, closeTo(restingPane - 300, 8));
  });

  testWidgets('landscape keeps the side rail, wherever the strip is set', (
    tester,
  ) async {
    await _pumpScreen(tester);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('sessionTabScroll'))).width,
      closeTo(kNavRailWidth, 1),
    );
    expect(_bar, findsNothing);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('a tab menu opened at the bottom stays on screen', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('sessionTabContent-session-1')),
        matching: find.byIcon(PhosphorIconsRegular.dotsThreeVertical),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final log = find.text('Connection log');
    expect(log, findsOneWidget);
    final row = tester.getRect(log);
    expect(row.top, greaterThanOrEqualTo(0));
    expect(row.bottom, lessThanOrEqualTo(_screenHeight(tester)));
  });
}

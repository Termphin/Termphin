import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/services/app/app_commands.dart';
import 'package:termphin/services/platform/desktop_tray.dart';
import 'package:termphin/services/platform/tray_menu.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/settings/desktop_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/window/desktop_tray_host.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

class _FakeTray implements TrayBackend {
  _FakeTray({this.available = true});

  final bool available;
  List<TrayMenuEntry>? menu;
  String? tooltip;
  bool visible = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> show({
    required List<TrayMenuEntry> menu,
    required String tooltip,
    required VoidCallback onActivate,
  }) async {
    this.menu = menu;
    this.tooltip = tooltip;
    visible = true;
  }

  @override
  Future<void> hide() async => visible = false;
}

class _FakeWindow implements DesktopWindowControls {
  Future<void> Function()? closeHandler;
  int hidden = 0;
  int shown = 0;
  int quits = 0;

  @override
  set onCloseRequested(Future<void> Function()? handler) =>
      closeHandler = handler;

  @override
  Future<void> show() async => shown++;

  @override
  Future<void> hide() async => hidden++;

  @override
  Future<void> quit() async => quits++;
}

void main() {
  final t = AppLocale.en.buildSync();
  late FakeSshBackend backend;
  late SshSessionManager manager;
  late _FakeWindow window;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await loadAppSettings();
    backend = FakeSshBackend();
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    window = _FakeWindow();
  });

  tearDown(() => manager.dispose());

  Future<_FakeTray> mount(
    WidgetTester tester, {
    bool trayAvailable = true,
  }) async {
    final tray = _FakeTray(available: trayAvailable);
    final pageKey = GlobalKey();
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(
          FakeProfileStorage([profileFixture()]),
        ),
      ],
    );
    await container.read(profilesProvider.notifier).loadProfiles();
    await pumpTestApp(
      tester,
      DesktopTrayHost(
        navigatorContext: () => pageKey.currentContext,
        tray: DesktopTray.test(tray),
        window: window,
        manager: manager,
        child: SizedBox(key: pageKey),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
    return tray;
  }

  Future<void> close(WidgetTester tester) async {
    unawaited(window.closeHandler!());
    await tester.pumpAndSettle();
  }

  List<String> labels(List<TrayMenuEntry> menu) => [
    for (final entry in menu)
      if (!entry.separator) entry.label,
  ];

  group('the tray menu', () {
    testWidgets('lists connected sessions and not a detached one', (
      tester,
    ) async {
      final profile = profileFixture();
      await manager.startSession(profile, sessionId: 'live');
      await manager.startSession(profile, sessionId: 'parked');
      await manager.stopSession('parked');
      final tray = await mount(tester);

      final sessions = labels(
        tray.menu!,
      ).where((label) => label.startsWith('${profile.name} - '));
      expect(sessions, hasLength(1));
      expect(tray.tooltip, t.window.trayTooltip(n: 1));
    });

    testWidgets('says so when nothing is connected', (tester) async {
      final tray = await mount(tester);

      final empty = tray.menu!.firstWhere(
        (entry) => entry.label == t.window.trayNoSessions,
      );
      expect(empty.enabled, isFalse);
    });

    testWidgets('goes away with the setting', (tester) async {
      final tray = await mount(tester);
      expect(tray.visible, isTrue);

      await closeToTraySetting.set(false);
      await tester.pumpAndSettle();

      expect(tray.visible, isFalse);
    });
  });

  group('closing the window', () {
    testWidgets('asks the first time, and keeps running when told to', (
      tester,
    ) async {
      await mount(tester);

      await close(tester);
      expect(find.text(t.window.closeAskTitle), findsOneWidget);
      await tester.tap(find.text(t.window.closeAskKeep));
      await tester.pumpAndSettle();

      expect(window.hidden, 1);
      expect(window.quits, 0);
      expect(closeToTraySetting.value, isTrue);

      await close(tester);
      expect(find.text(t.window.closeAskTitle), findsNothing);
      expect(window.hidden, 2);
    });

    testWidgets('a first "Quit" quits without asking a second time', (
      tester,
    ) async {
      await manager.startSession(profileFixture(), sessionId: 'live');
      await mount(tester);

      await close(tester);
      await tester.tap(find.text(t.window.closeAskQuit));
      await tester.pumpAndSettle();

      expect(find.text(t.window.quitConfirmTitle), findsNothing);
      expect(window.quits, 1);
      expect(closeToTraySetting.value, isFalse);
    });

    testWidgets('quits where there is no tray to hide in', (tester) async {
      await mount(tester, trayAvailable: false);

      await close(tester);

      expect(find.text(t.window.closeAskTitle), findsNothing);
      expect(window.hidden, 0);
      expect(window.quits, 1);
    });
  });

  group('quitting', () {
    testWidgets('with sessions connected, asks first', (tester) async {
      await manager.startSession(profileFixture(), sessionId: 'live');
      await mount(tester);

      AppCommands.instance.run(AppCommand.quit);
      await tester.pumpAndSettle();
      expect(find.text(t.window.quitConfirmBody(n: 1)), findsOneWidget);
      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      expect(window.quits, 0);

      AppCommands.instance.run(AppCommand.quit);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.window.quitConfirm));
      await tester.pumpAndSettle();
      expect(window.quits, 1);
    });

    testWidgets('with nothing connected, just quits', (tester) async {
      await mount(tester);

      AppCommands.instance.run(AppCommand.quit);
      await tester.pumpAndSettle();

      expect(window.quits, 1);
    });
  });
}

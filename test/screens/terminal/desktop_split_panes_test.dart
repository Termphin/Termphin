import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/screens/main_shell.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/app/app_commands.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/terminal/floating_action_dock.dart';
import 'package:termphin/widgets/terminal/session_view.dart';
import 'package:termphin/widgets/terminal/split_tree_layout.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

Future<(ProviderContainer, FakeSshBackend, SshSessionManager, List<SshProfile>)>
_makeEnv() async {
  final first = profileFixture(id: 'p1', name: 'Alpha', host: 'alpha.example');
  final second = profileFixture(id: 'p2', name: 'Beta', host: 'beta.example');
  final backend = FakeSshBackend();
  final manager = SshSessionManager.test(
    remoteAgentService: FakeRemoteAgentService(backend),
    serviceFactory: backend.createService,
  );
  final container = ProviderContainer.test(
    overrides: [
      sshSessionManagerProvider.overrideWithValue(manager),
      profileStorageProvider.overrideWithValue(
        FakeProfileStorage([first, second]),
      ),
    ],
  );
  container.read(profilesProvider);
  await container.read(profilesProvider.notifier).loadProfiles();
  return (container, backend, manager, [first, second]);
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

bool _isPaneActive(WidgetTester tester, String id) => tester
    .widget<SessionView>(
      find.descendant(
        of: find.byKey(ValueKey('splitTreePane-$id')),
        matching: find.byType(SessionView),
      ),
    )
    .isActive;

String _otherPaneId(WidgetTester tester, Set<String> known) {
  final matches = find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('splitTreePane-') &&
            !known.contains(
              (w.key! as ValueKey<String>).value.substring(
                'splitTreePane-'.length,
              ),
            ),
      )
      .evaluate();
  final key = matches.single.widget.key! as ValueKey<String>;
  return key.value.substring('splitTreePane-'.length);
}

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
  });

  tearDown(() {
    AppCommands.instance.uninstall();
  });

  testWidgets('phone floating action dock leaves out split and zoom', (
    tester,
  ) async {
    final (container, backend, manager, profiles) = await _makeEnv();
    addTearDown(manager.dispose);

    await pumpTestApp(
      tester,
      TerminalScreen(initialSessionId: 's1', initialProfile: profiles.first),
      container: container,
    );
    await backend.connectCalled.future;
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionDock),
        matching: find.byType(Icon),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.actionDock.paste), findsOneWidget);
    expect(find.text(t.actionDock.split), findsNothing);
    expect(find.text(t.actionDock.zoom), findsNothing);
  });

  testWidgets(
    'desktop Split menu splits panes, switches presets, and Zoom toggles',
    (tester) async {
      final (container, backend, manager, profiles) = await _makeEnv();
      addTearDown(manager.dispose);

      await pumpTestApp(
        tester,
        TerminalScreen(initialSessionId: 's1', initialProfile: profiles.first),
        container: container,
      );
      tester.view.physicalSize = const Size(1400, 900);
      await backend.connectCalled.future;
      await tester.pumpAndSettle();

      final zoomButton = tester.widget<TextButton>(
        find.byKey(const ValueKey('actionBar-zoom')),
      );
      expect(zoomButton.onPressed, isNull);
      expect(find.text('Zoom pane (Ctrl+Shift+Z)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tabMenu-s1')));
      await tester.pumpAndSettle();
      expect(find.text(t.terminal.splitWith), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('actionBar-split')),
      );
      await tester.tap(find.byKey(const ValueKey('actionBar-split')));
      await tester.pumpAndSettle();
      expect(find.text(t.commands.splitRight), findsOneWidget);
      expect(find.text(t.commands.splitDown), findsOneWidget);
      expect(find.text(t.terminal.splitPresetColumns), findsOneWidget);
      expect(find.text(t.terminal.splitPresetRows), findsOneWidget);
      expect(find.text(t.terminal.splitPresetGrid), findsOneWidget);
      expect(find.text(t.terminal.splitPresetMainAndStack), findsOneWidget);

      await tester.tap(find.text(t.commands.splitRight));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitTreeLayout), findsOneWidget);
      final s2 = _otherPaneId(tester, {'s1'});
      final rect1 = tester.getRect(find.byKey(const ValueKey('splitTreePane-s1')));
      final rect2 = tester.getRect(find.byKey(ValueKey('splitTreePane-$s2')));
      expect(rect1.right, lessThan(rect2.left));

      await tester.ensureVisible(
        find.byKey(const ValueKey('actionBar-split')),
      );
      await tester.tap(find.byKey(const ValueKey('actionBar-split')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.terminal.splitPresetRows));
      await tester.pumpAndSettle();

      final row1 = tester.getRect(find.byKey(const ValueKey('splitTreePane-s1')));
      final row2 = tester.getRect(find.byKey(ValueKey('splitTreePane-$s2')));
      expect(row1.bottom, lessThan(row2.top));

      await tester.ensureVisible(find.byKey(const ValueKey('actionBar-zoom')));
      await tester.tap(find.byKey(const ValueKey('actionBar-zoom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('splitTreePane-s1')), findsNothing);
      expect(find.byKey(ValueKey('splitTreePane-$s2')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('actionBar-zoom')));
      await tester.tap(find.byKey(const ValueKey('actionBar-zoom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('splitTreePane-s1')), findsOneWidget);
      expect(find.byKey(ValueKey('splitTreePane-$s2')), findsOneWidget);
    },
    variant: _linux,
  );

  testWidgets('refuses to split when the pane would become too small', (
    tester,
  ) async {
    final (container, backend, manager, profiles) = await _makeEnv();
    addTearDown(manager.dispose);

    await pumpTestApp(
      tester,
      TerminalScreen(initialSessionId: 's1', initialProfile: profiles.first),
      container: container,
    );
    tester.view.physicalSize = const Size(520, 480);
    await backend.connectCalled.future;
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('actionBar-split')));
    await tester.tap(find.byKey(const ValueKey('actionBar-split')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.commands.splitRight));
    await tester.pumpAndSettle();

    expect(find.text(t.terminal.splitTooSmall), findsOneWidget);
    expect(find.byType(SplitTreeLayout), findsNothing);
  }, variant: _linux);

  testWidgets('MainShell shortcuts split, navigate, resize, and zoom panes', (
    tester,
  ) async {
    final (container, backend, manager, profiles) = await _makeEnv();
    addTearDown(manager.dispose);

    AppCommands.instance.install();
    await pumpTestApp(tester, const MainShell(), container: container);
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump();
    container
        .read(terminalOverlayProvider.notifier)
        .show('s1', profiles.first, scope: SiblingScope.none);
    await tester.pump();
    await tester.pump();
    await backend.connectCalled.future;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      AppCommands.instance.claims(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          logicalKey: LogicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );

    await _press(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
    await tester.pump();
    expect(find.byType(SplitTreeLayout), findsNothing);

    await _press(tester, LogicalKeyboardKey.keyD, control: true, shift: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Beta').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final s2 = _otherPaneId(tester, {'s1'});
    expect(_isPaneActive(tester, s2), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(
      AppCommands.instance.claims(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          logicalKey: LogicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    expect(
      AppCommands.instance.claims(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowRight,
          logicalKey: LogicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_isPaneActive(tester, 's1'), isTrue);
    expect(_isPaneActive(tester, s2), isFalse);

    final widthBefore = tester
        .getSize(find.byKey(const ValueKey('splitTreePane-s1')))
        .width;
    await _press(
      tester,
      LogicalKeyboardKey.arrowRight,
      alt: true,
      shift: true,
    );
    await tester.pump();
    final widthAfter = tester
        .getSize(find.byKey(const ValueKey('splitTreePane-s1')))
        .width;
    expect(widthAfter, greaterThan(widthBefore));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      AppCommands.instance.claims(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowUp,
          logicalKey: LogicalKeyboardKey.arrowUp,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    await _press(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('splitTreePane-s1')), findsOneWidget);
    expect(find.byKey(ValueKey('splitTreePane-$s2')), findsNothing);

    await _press(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
    await tester.pump();
    expect(find.byKey(ValueKey('splitTreePane-$s2')), findsOneWidget);

    await _press(
      tester,
      LogicalKeyboardKey.keyD,
      control: true,
      shift: true,
      alt: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Alpha').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final s3 = _otherPaneId(tester, {'s1', s2});
    final r1 = tester.getRect(find.byKey(const ValueKey('splitTreePane-s1')));
    final r3 = tester.getRect(find.byKey(ValueKey('splitTreePane-$s3')));
    expect(r1.bottom, lessThan(r3.top));
  }, variant: _linux);
}

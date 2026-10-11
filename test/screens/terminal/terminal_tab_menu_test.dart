import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/screens/terminal/terminal_screen.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/theme/theme.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

/// [connectError] leaves the tab failed rather than connected.
Future<SshSessionManager> _openMenu(
  WidgetTester tester, {
  Object? connectError,
  FakeSshBackend? backend,
}) async {
  final profile = profileFixture();
  backend ??= FakeSshBackend();
  backend.connectError = connectError;
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
  if (connectError == null) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  await tester.tap(find.byKey(const ValueKey('tabMenu-session-1')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return manager;
}

/// Every row of the open menu, top to bottom, by the key's last part.
List<String> _rows(WidgetTester tester) {
  final keyed = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> &&
        RegExp(
          r'^(tabMenuHeader|viewModeSegments|tabMenuSection|tabMenuItem)-',
        ).hasMatch(key.value);
  });
  final rows = keyed.evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [
    for (final e in rows)
      switch ((e.widget.key! as ValueKey<String>).value) {
        final k when k.startsWith('tabMenuHeader') => 'header',
        final k when k.startsWith('viewModeSegments') => 'modes',
        final k when k.startsWith('tabMenuSection') => 'section',
        final k => k.split('-').last,
      },
  ];
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

  group('ending the session', () {
    Future<void> confirmEnd(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('tabMenuItem-session-1-endSession')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'End session'));
      await tester.pump();
    }

    testWidgets('closes the tab before the server answers', (tester) async {
      final answer = Completer<SSHRunResult>();
      final backend = FakeSshBackend();
      final manager = await _openMenu(tester, backend: backend);
      backend.runWithResult = (_) => answer.future;

      await confirmEnd(tester);

      expect(find.byKey(const ValueKey('tabMenu-session-1')), findsNothing);
      expect(manager.getSession('session-1'), isNull);

      answer.complete(
        SSHRunResult(
          output: Uint8List(0),
          stdout: Uint8List(0),
          stderr: Uint8List(0),
          exitCode: 0,
          exitSignal: null,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('says so when the server would not end it', (tester) async {
      final backend = FakeSshBackend()
        ..runWithResult = (_) async => SSHRunResult(
          output: Uint8List(0),
          stdout: Uint8List(0),
          stderr: Uint8List.fromList(utf8.encode('permission denied')),
          exitCode: 1,
          exitSignal: null,
        );
      await _openMenu(tester, backend: backend);

      await confirmEnd(tester);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.textContaining("Couldn't end the session on"),
        findsOneWidget,
      );
      expect(find.textContaining('permission denied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('closing the tab', () {
    testWidgets('still drops the tab when the session fails to close', (
      tester,
    ) async {
      final backend = FakeSshBackend();
      final manager = await _openMenu(tester, backend: backend);
      backend.latestService.fakeSession.closeError = Exception('boom');

      await tester.tap(
        find.byKey(const ValueKey('tabMenuItem-session-1-close')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tabMenu-session-1')), findsNothing);
      expect(manager.stripHoldsTab('session-1'), isFalse);
    });
  });

  testWidgets('whose tab, the switch, what it does, then leaving', (
    tester,
  ) async {
    await _openMenu(tester);

    expect(_rows(tester), [
      'header',
      'modes',
      'section',
      'splitWith',
      'manageTunnels',
      'rename',
      'viewLog',
      'close',
      'endSession',
    ]);
    final close = tester.getRect(
      find.byKey(const ValueKey('tabMenuItem-session-1-close')),
    );
    final end = tester.getRect(
      find.byKey(const ValueKey('tabMenuItem-session-1-endSession')),
    );
    expect(end.top, greaterThan(close.bottom));
    expect(end.left, close.left);
    expect(end.width, close.width);
  });

  testWidgets('the header names the session and where it logs in', (
    tester,
  ) async {
    final manager = await _openMenu(tester);

    final header = find.byKey(const ValueKey('tabMenuHeader-session-1'));
    final profile = profileFixture();
    final session = SessionTab.displayName(manager.muxNameFor('session-1')!);
    expect(
      find.descendant(of: header, matching: find.text(session)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text(profile.name)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.text('${profile.username}@${profile.host}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a tab without a persistent session goes by the machine', (
    tester,
  ) async {
    await _openMenu(tester, connectError: Exception('No route to host'));

    final header = find.byKey(const ValueKey('tabMenuHeader-session-1'));
    expect(
      find.descendant(of: header, matching: find.text(profileFixture().name)),
      findsOneWidget,
    );
  });

  testWidgets('a tab not connected offers a retry and no switch', (
    tester,
  ) async {
    await _openMenu(tester, connectError: Exception('No route to host'));

    final rows = _rows(tester);
    expect(rows.first, 'header');
    expect(rows, isNot(contains('modes')));
    expect(rows, contains('reconnect'));
  });

  testWidgets('the mode switch is labelled, not just icons', (tester) async {
    await _openMenu(tester);

    final modes = find.byKey(const ValueKey('viewModeSegments-session-1'));
    expect(
      find.descendant(of: modes, matching: find.text('Terminal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: modes, matching: find.text('Files')),
      findsOneWidget,
    );
  });

  testWidgets('the picked side is a raised thumb, concentric with its track', (
    tester,
  ) async {
    await _openMenu(tester);
    final thumbFinder = find.byKey(const ValueKey('viewModeThumb'));
    final trackFinder = find
        .ancestor(of: thumbFinder, matching: find.byType(Container))
        .last;
    final colors = tester.element(thumbFinder).colors;

    final thumb =
        tester.widget<DecoratedBox>(thumbFinder).decoration as BoxDecoration;
    final track =
        tester.widget<Container>(trackFinder).decoration! as BoxDecoration;
    double radius(BoxDecoration d) =>
        (d.borderRadius! as BorderRadius).topLeft.x;
    final inset =
        (tester.getSize(trackFinder).height -
            tester.getSize(thumbFinder).height) /
        2;

    expect(radius(thumb), radius(track) - inset);
    expect(thumb.color, colors.surfaceOffset2);
    expect(track.color, colors.backgroundPrimary);

    final modes = find.byKey(const ValueKey('viewModeSegments-session-1'));
    Color? label(String text) => tester
        .widget<Text>(find.descendant(of: modes, matching: find.text(text)))
        .style
        ?.color;
    expect(label('Terminal'), colors.textPrimary);
    expect(label('Files'), colors.textSecondary);
  });

  testWidgets('only ending the session is red', (tester) async {
    await _openMenu(tester);
    final error = AppColors.dark.error;

    Color? colorOf(String action) => tester
        .renderObject<RenderParagraph>(
          find
              .descendant(
                of: find.byKey(ValueKey('tabMenuItem-session-1-$action')),
                matching: find.byType(RichText),
              )
              .last,
        )
        .text
        .style
        ?.color;

    expect(colorOf('endSession'), error);
    for (final action in ['close', 'rename', 'splitWith', 'viewLog']) {
      expect(colorOf(action), isNot(error), reason: action);
    }
  });
}

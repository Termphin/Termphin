import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/widgets/sftp/sftp_browser_view.dart';
import 'package:termphin/widgets/ssh/connecting_view.dart';
import 'package:termphin/widgets/ssh/connection_quality_pill.dart';
import 'package:termphin/widgets/terminal/session_view.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

import '../../support/fixtures.dart';
import '../../support/platform_mocks.dart';
import '../../support/ssh_fakes.dart';
import '../../support/test_app.dart';

void main() {
  late FakeSshBackend backend;
  late FakeRemoteAgentService agent;
  late SshSessionManager manager;
  late ProviderContainer container;
  late SshProfile profile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await loadAppSettings();
    profile = profileFixture();
    backend = FakeSshBackend();
    agent = FakeRemoteAgentService(backend);
    manager = SshSessionManager.test(
      remoteAgentService: agent,
      serviceFactory: backend.createService,
    );
    await manager.startSession(profile, sessionId: 'session-1');
    backend.calls.clear();
    backend.connectCalled = Completer<void>();
    container = ProviderContainer.test(
      overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
    );
  });

  tearDown(() => manager.dispose());

  final viewKey = GlobalKey<SessionViewState>();

  Future<SessionViewState> pump(
    WidgetTester tester, {
    SessionViewMode mode = SessionViewMode.terminal,
    bool isActive = true,
  }) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: SessionView(
          key: viewKey,
          sessionKey: ('session-1', profile),
          viewMode: mode,
          isActive: isActive,
          onClose: () {},
        ),
      ),
      container: container,
    );
    await container
        .read(sshConnectionProvider(('session-1', profile)).notifier)
        .connect();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return viewKey.currentState!;
  }

  List<MethodCall> writes() =>
      backend.calls.where((c) => c.method == 'write').toList();

  String written() => [
    for (final call in writes())
      utf8.decode((call.arguments as Map)['data'] as Uint8List),
  ].join();

  group('which pane a tab shows', () {
    testWidgets('the terminal once the session is up', (tester) async {
      await pump(tester);
      expect(find.byType(TerminalPane), findsOneWidget);
    });

    testWidgets('the file browser in sftp mode', (tester) async {
      await pump(tester, mode: SessionViewMode.sftp);
      expect(find.byType(SftpBrowserView), findsOneWidget);
    });

    testWidgets('keeps the terminal built behind the browser', (tester) async {
      await pump(tester, mode: SessionViewMode.sftp);
      expect(find.byType(TerminalPane, skipOffstage: false), findsOneWidget);
      expect(manager.getSession('session-1'), isNotNull);
    });

    testWidgets('the connecting screen while the link is still being made', (
      tester,
    ) async {
      backend.connectGate = Completer<void>();
      await pumpTestApp(
        tester,
        Scaffold(
          body: SessionView(
            sessionKey: ('session-2', profile),
            viewMode: SessionViewMode.terminal,
            isActive: true,
            onClose: () {},
          ),
        ),
        container: container,
      );
      unawaited(
        container
            .read(sshConnectionProvider(('session-2', profile)).notifier)
            .connect(),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(ConnectingView), findsOneWidget);
      expect(find.byType(TerminalPane), findsNothing);
      backend.connectGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('through a reconnect', () {
    /// Drops the session and holds the retry at the handshake.
    Future<void> dropAndHold(WidgetTester tester) async {
      backend.connectGate = Completer<void>();
      manager.markSessionDropped('session-1');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        container.read(sshConnectionProvider(('session-1', profile))).status,
        ConnectionStatus.reconnecting,
      );
    }

    Future<void> release(WidgetTester tester) async {
      backend.connectGate!.complete();
      backend.connectGate = null;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('keeps the terminal on screen instead of the connect screen', (
      tester,
    ) async {
      await pump(tester);
      await dropAndHold(tester);

      expect(find.byType(TerminalPane), findsOneWidget);
      expect(find.byType(ConnectingView), findsNothing);
      expect(find.byType(ReconnectingIndicator), findsOneWidget);

      await release(tester);
      expect(find.byType(TerminalPane), findsOneWidget);
      expect(find.byType(ReconnectingIndicator), findsNothing);
    });

    testWidgets('sends what was typed meanwhile once the terminal is back', (
      tester,
    ) async {
      final state = await pump(tester);
      await dropAndHold(tester);

      state.writeRaw(Uint8List.fromList(utf8.encode('ls')));
      state.writeRaw(Uint8List.fromList([0x0d]));
      await tester.pump();
      expect(writes(), isEmpty);

      await release(tester);

      expect(written(), 'ls');
    });

    testWidgets('a resumed session keeps the very same terminal', (
      tester,
    ) async {
      agent.remoteVersion = '0.12.0';
      backend.attachOutput = (command) => utf8.encode(
        command.contains('--resume')
            ? '\x1b]5380;termphin-resume-end\x07'
                  '\x1b]5383;termphin-offset;3:10\x07'
            : '\x1b]5380;termphin-replay-end\x07'
                  '\x1b]5383;termphin-offset;3:10\x07',
      );
      await manager.disconnectSession('session-1');
      await pump(tester);
      final before = tester.state(find.byType(TerminalPane));

      await dropAndHold(tester);
      await release(tester);

      expect(
        (backend.calls.lastWhere((c) => c.method == 'startShell').arguments
            as Map)['command'],
        contains('--resume 3:10'),
      );
      expect(tester.state(find.byType(TerminalPane)), same(before));
      expect(find.byType(ReconnectingIndicator), findsNothing);
    });

    testWidgets('a failed reconnect still ends on the error card', (
      tester,
    ) async {
      await pump(tester);
      backend.connectError = const SshConnectException(
        SshFailureReason.authFailed,
        'denied',
      );
      manager.markSessionDropped('session-1');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(TerminalPane), findsNothing);
      expect(find.byType(ReconnectingIndicator), findsNothing);
    });
  });

  group('writing to the session', () {
    testWidgets('writeRaw sends the bytes it was handed, untouched', (
      tester,
    ) async {
      final state = await pump(tester);
      state.writeRaw(Uint8List.fromList([0x1b, 0x5b, 0x41]));
      await tester.pump();

      expect(writes(), hasLength(1));
      expect((writes().single.arguments as Map)['data'], [0x1b, 0x5b, 0x41]);
    });

    testWidgets('a paste puts the clipboard into the session', (tester) async {
      final clipboard = ClipboardMock()..install();
      addTearDown(clipboard.uninstall);
      clipboard.text = 'echo hello';

      final state = await pump(tester);
      await state.handlePaste();
      await tester.pump();

      expect(written(), contains('echo hello'));
    });

    testWidgets(
      'a paste that outlives the tab does not throw once the clipboard answers',
      (tester) async {
        final clipboardAnswer = Completer<Object?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) {
              if (call.method == 'Clipboard.getData') {
                return clipboardAnswer.future;
              }
              return Future.value();
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        final state = await pump(tester);
        unawaited(state.handlePaste());
        await tester.pump();

        await pumpTestApp(
          tester,
          const SizedBox.shrink(),
          container: container,
        );

        clipboardAnswer.complete(<String, Object?>{'text': 'echo hello'});
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the modifier keys', () {
    testWidgets('start off', (tester) async {
      final state = await pump(tester);
      expect(state.ctrlMode.value.name, 'off');
      expect(state.altMode.value.name, 'off');
      expect(state.shiftMode.value.name, 'off');
    });

    testWidgets('are exposed for the toolbar above to drive', (tester) async {
      final state = await pump(tester);
      expect(state.ctrlMode, isNotNull);
      expect(state.altMode, isNotNull);
      expect(state.shiftMode, isNotNull);
    });
  });

  testWidgets('focusing the terminal does not throw when it is not shown', (
    tester,
  ) async {
    final state = await pump(tester, mode: SessionViewMode.sftp);
    state.focusTerminal();
    await tester.pump();
  });

  testWidgets('an inactive tab still builds and still writes', (tester) async {
    final state = await pump(tester, isActive: false);
    state.writeRaw(Uint8List.fromList([0x61]));
    await tester.pump();

    expect(written(), 'a');
  });

  group('a failed connection', () {
    final t = AppLocale.en.buildSync();

    /// Connects a tab whose session does not exist yet, so the attempt runs
    /// instead of attaching to the one [setUp] already started.
    Future<void> pumpFailing(
      WidgetTester tester, {
      required Object error,
      AuthMethod authMethod = AuthMethod.password,
    }) async {
      backend.connectError = error;
      final failing = profileFixture(authMethod: authMethod);
      await pumpTestApp(
        tester,
        Scaffold(
          body: SessionView(
            sessionKey: ('session-failing', failing),
            viewMode: SessionViewMode.terminal,
            isActive: true,
            onClose: () {},
          ),
        ),
        container: container,
      );
      await container
          .read(sshConnectionProvider(('session-failing', failing)).notifier)
          .connect();
      await tester.pump();
    }

    testWidgets('says what a rejected key means, not the thrown text', (
      tester,
    ) async {
      await pumpFailing(
        tester,
        authMethod: AuthMethod.privateKey,
        error: const SshConnectException(
          SshFailureReason.authFailed,
          'Authentication failed. Check your credentials.',
        ),
      );

      expect(find.text(t.connection.errors.authFailedKey), findsOneWidget);
      expect(
        find.text('Authentication failed. Check your credentials.'),
        findsNothing,
      );
    });

    testWidgets('reads the password wording when that is what was sent', (
      tester,
    ) async {
      await pumpFailing(
        tester,
        error: const SshConnectException(
          SshFailureReason.authFailed,
          'Authentication failed. Check your credentials.',
        ),
      );

      expect(find.text(t.connection.errors.authFailedPassword), findsOneWidget);
    });

    testWidgets('names the passphrase when the key could not be unlocked', (
      tester,
    ) async {
      await pumpFailing(
        tester,
        authMethod: AuthMethod.privateKey,
        error: const SshConnectException(
          SshFailureReason.keyPassphrase,
          'The key could not be unlocked. Check its passphrase.',
        ),
      );

      expect(find.text(t.connection.errors.keyPassphrase), findsOneWidget);
    });

    testWidgets('still shows the driver text when nothing classified it', (
      tester,
    ) async {
      await pumpFailing(
        tester,
        error: Exception('SSH error: no matching key exchange'),
      );

      expect(find.text('SSH error: no matching key exchange'), findsOneWidget);
    });
  });
}

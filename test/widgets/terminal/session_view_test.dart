import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/platform/clipboard_image.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/terminal/local_agent_service.dart';
import 'package:termphin/services/terminal/local_agent_transport.dart';
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
      await tester.pump(const Duration(milliseconds: 300));

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
          () => TestDefaultBinaryMessengerBinding
              .instance
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

  group('the keyboard on a tab that comes on screen', () {
    bool terminalFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TerminalView>() !=
        null;

    /// Runs [body] as a desktop, putting the platform back even when it
    /// fails - a leftover override fails every test after it.
    Future<void> asDesktop(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('a desktop types into it straight away', (tester) async {
      var focused = false;
      await asDesktop(() async {
        await pump(tester);
        await tester.pump();
        focused = terminalFocused();
      });

      expect(focused, isTrue);
    });

    testWidgets('a desktop types into a tab switched to', (tester) async {
      var before = true;
      var after = false;
      await asDesktop(() async {
        await pump(tester, isActive: false);
        before = terminalFocused();

        await pumpTestApp(
          tester,
          Scaffold(
            body: SessionView(
              key: viewKey,
              sessionKey: ('session-1', profile),
              viewMode: SessionViewMode.terminal,
              isActive: true,
              onClose: () {},
            ),
          ),
          container: container,
        );
        await tester.pump();
        after = terminalFocused();
      });

      expect(before, isFalse);
      expect(after, isTrue);
    });

    testWidgets('a phone waits for a tap', (tester) async {
      await pump(tester);
      await tester.pump();

      expect(terminalFocused(), isFalse);
    });
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

  group('local clipboard image paste', () {
    testWidgets(
      'pasting an image on This computer writes a temp file and pastes its quoted path',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final tempDir = Directory.systemTemp.createTempSync(
          'termphin-local-paste-',
        );
        final stdinWrites = <String>[];
        final fakeStdin = StreamController<List<int>>();
        fakeStdin.stream.listen((bytes) => stdinWrites.add(utf8.decode(bytes)));
        final localAgent = _FakeLocalAgent(windows: true);
        final localManager = SshSessionManager.test(
          remoteAgentService: agent,
          serviceFactory: backend.createService,
          localAgentService: localAgent,
          localTransportFactory: () => LocalAgentTransport(
            startProcess: (_, _, _) async => _FakeProcess(
              stdinController: fakeStdin,
              onStart: (stdoutController) {
                stdoutController.add(
                  utf8.encode(
                    '\x1b]5384;termphin-master;0.21.0\x07'
                    '\x1b]5380;termphin-replay-end\x07',
                  ),
                );
              },
            ),
          ),
        );
        final clipboard = ClipboardMock()..install();
        debugClipboardImageReader = () async =>
            Uint8List.fromList([137, 80, 78, 71]);
        debugLocalClipboardDirectory = tempDir;
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = null;
          debugClipboardImageReader = null;
          debugLocalClipboardDirectory = null;
          clipboard.uninstall();
          localManager.dispose();
          unawaited(fakeStdin.close());
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final localProfile = localComputerProfile(name: 'This computer');
        await localManager.startSession(localProfile, sessionId: 'local-1');
        final localContainer = ProviderContainer.test(
          overrides: [
            sshSessionManagerProvider.overrideWithValue(localManager),
          ],
        );
        final localKey = GlobalKey<SessionViewState>();
        await pumpTestApp(
          tester,
          Scaffold(
            body: SessionView(
              key: localKey,
              sessionKey: ('local-1', localProfile),
              viewMode: SessionViewMode.terminal,
              isActive: true,
              onClose: () {},
            ),
          ),
          container: localContainer,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.runAsync(() => localKey.currentState!.handlePaste());
        await tester.pump();

        final files = tempDir.listSync().whereType<File>().toList();
        expect(files, hasLength(1));
        expect(stdinWrites.join(), contains('"${files.single.path}"'));
      },
    );
  });
}

class _FakeLocalAgent extends LocalAgentService {
  _FakeLocalAgent({required bool windows})
    : super(
        operatingSystem: windows ? 'Windows' : 'Linux',
        architecture: 'x86_64',
        homeDirectory: r'C:\Users\tester',
      );

  @override
  Future<String> ensureInstalled() async =>
      r'C:\Users\tester\AppData\Local\termphin\bin\termphin-agent.exe';
}

class _FakeProcess implements Process {
  _FakeProcess({
    required StreamController<List<int>> stdinController,
    required void Function(StreamController<List<int>> stdout) onStart,
  }) : _stdin = IOSink(stdinController.sink) {
    scheduleMicrotask(() => onStart(_stdout));
  }

  final IOSink _stdin;
  final _stdout = StreamController<List<int>>.broadcast();
  final _stderr = StreamController<List<int>>.broadcast();
  final _exitCode = Completer<int>();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    if (!_exitCode.isCompleted) _exitCode.complete(0);
    return true;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/push/machine_shell.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/terminal/local_agent_service.dart';
import 'package:termphin/services/terminal/local_agent_transport.dart';
import 'package:termphin/services/terminal/terminal_text.dart';
import 'package:termphin/utils/platform_info.dart';

import '../../support/secure_storage_channel.dart';
import '../../support/ssh_fakes.dart';

class _FakeLocalAgentService extends LocalAgentService {
  _FakeLocalAgentService({this.windows = false})
    : super(
        operatingSystem: windows ? 'Windows' : 'Linux',
        architecture: 'x86_64',
        homeDirectory: '/tmp/home',
      );

  final bool windows;
  final List<RemoteMuxSession> sessions = [];
  final List<String> killed = [];
  final List<(String, String)> renamed = [];
  final List<(String, String, String)> deviceCommands = [];
  final List<String> shellCommands = [];
  int listCalls = 0;
  int ensureInstalledCalls = 0;

  @override
  bool get isWindows => windows;

  @override
  Future<String> ensureInstalled() async {
    ensureInstalledCalls++;
    return windows
        ? r'C:\Users\alice\AppData\Local\termphin\bin\termphin-agent.exe'
        : '/home/alice/.local/lib/termphin/termphin-agent';
  }

  @override
  Future<Uint8List> runShellCommand(String command) async {
    shellCommands.add(command);
    return Uint8List.fromList(utf8.encode(windows ? '' : 'Linux\n'));
  }

  @override
  Future<List<RemoteMuxSession>> list() async {
    listCalls++;
    return List.of(sessions);
  }

  @override
  Future<void> kill(String name) async {
    killed.add(name);
    sessions.removeWhere((s) => s.name == name);
  }

  @override
  Future<void> rename(String oldName, String newName) async {
    renamed.add((oldName, newName));
  }

  @override
  Future<void> deviceCommand(String verb, String name, String deviceId) async {
    deviceCommands.add((verb, name, deviceId));
  }
}

class _FakeSink implements IOSink {
  final List<List<int>> added = [];
  final Completer<void> _done = Completer<void>();

  @override
  void add(List<int> data) => added.add(List<int>.from(data));

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAttachProcess implements Process {
  // ignore: close_sinks - fake in-memory sink closed in tests
  final _FakeSink fakeStdin = _FakeSink();
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>();
  final Completer<int> exitCompleter = Completer<int>();

  @override
  IOSink get stdin => fakeStdin;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!exitCompleter.isCompleted) {
      unawaited(stdoutController.close());
      unawaited(stderrController.close());
      exitCompleter.complete(0);
    }
    return true;
  }

  @override
  int get pid => 1001;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSshBackend sshBackend;
  late _FakeLocalAgentService localService;
  late List<_FakeAttachProcess> startedProcesses;
  late List<String?> startedIn;
  late SshSessionManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    sshBackend = FakeSshBackend();
    localService = _FakeLocalAgentService();
    startedProcesses = [];
    startedIn = [];
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(sshBackend),
      serviceFactory: sshBackend.createService,
      localAgentService: localService,
      localTransportFactory: () => LocalAgentTransport(
        startProcess: (executable, arguments, workingDirectory) async {
          startedIn.add(workingDirectory);
          final proc = _FakeAttachProcess();
          startedProcesses.add(proc);
          unawaited(
            Future<void>.microtask(() {
              proc.stdoutController.add(
                utf8.encode(
                  '\x1b]5384;termphin-master;0.21.0\x07'
                  '\x1b]5380;termphin-replay-end\x07'
                  'local prompt> ',
                ),
              );
            }),
          );
          return proc;
        },
      ),
    );
  });

  tearDown(() => manager.dispose());

  test(
    'local profile survives _restoreOfflineTabs without being in storage',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({
        'session_tabs': [
          jsonEncode(
            SessionTab(
              tabId: 'local-1',
              profileId: kLocalProfileId,
              muxName: 'termphin_local',
              lastSeen: DateTime.utc(2026, 2, 1),
              wasConnected: true,
            ).toJson(),
          ),
          jsonEncode(
            SessionTab(
              tabId: 'gone-1',
              profileId: 'deleted-ssh-profile',
              muxName: 'termphin_gone',
              lastSeen: DateTime.utc(2026, 2, 1),
              wasConnected: true,
            ).toJson(),
          ),
        ],
      });

      await manager.init();

      expect(manager.tabs.map((s) => s.id), ['local-1']);
      final restored = manager.getSession('local-1');
      expect(restored, isNotNull);
      expect(restored!.profile.isLocal, isTrue);
      expect(restored.dropped, isTrue);
    },
  );

  test('Snap drops persisted local tabs during _restoreOfflineTabs', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    debugSnapPackageOverride = true;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      debugSnapPackageOverride = null;
    });
    SharedPreferences.setMockInitialValues({
      'session_tabs': [
        jsonEncode(
          SessionTab(
            tabId: 'local-1',
            profileId: kLocalProfileId,
            muxName: 'termphin_local',
            lastSeen: DateTime.utc(2026, 2, 1),
            wasConnected: true,
          ).toJson(),
        ),
      ],
    });

    await manager.init();

    expect(manager.tabs, isEmpty);
  });

  test(
    'listRemoteSessions, rename and kill route to LocalAgentService for local profile',
    () async {
      final profile = localComputerProfile(name: 'This computer');
      localService.sessions.add(
        RemoteMuxSession.fromMap({
          'name': 'shell-a',
          'windows': 1,
          'createdAt': 1700000000,
          'attached': false,
          'multiplexer': 'termphin',
        }),
      );

      final listed = await manager.listRemoteSessions(profile);
      expect(localService.listCalls, 1);
      expect(listed.map((s) => s.name), ['shell-a']);
      expect(sshBackend.calls, isEmpty);

      await manager.renameRemoteSession(profile, 'shell-a', 'shell-b');
      expect(localService.renamed, [('shell-a', 'shell-b')]);

      await manager.killRemoteSession(profile, 'shell-b');
      expect(localService.killed, ['shell-b']);
      expect(sshBackend.calls, isEmpty);
    },
  );

  test(
    'startSession opens a local tab with no SshService and delivers output',
    () async {
      final profile = localComputerProfile(name: 'This computer');

      final session = await manager.startSession(
        profile,
        sessionId: 'local-tab',
        muxName: 'local_1',
        initialWidth: 100,
        initialHeight: 30,
        replayRemoteHistory: true,
      );

      expect(sshBackend.calls, isEmpty);
      expect(session.sshService, isNull);
      expect(session.transport, isNotNull);
      expect(startedIn, ['/tmp/home']);
      expect(session.remoteShellType, RemoteShellType.unix);
      expect(session.masterVersion, '0.21.0');
      session.terminal.flush();
      expect(
        terminalBufferText(session.terminal.terminal.buffer),
        'local prompt>',
      );

      manager.sendInput('local-tab', Uint8List.fromList(utf8.encode('pwd\n')));
      expect(
        startedProcesses.single.fakeStdin.added.map(utf8.decode),
        contains('pwd\n'),
      );

      await manager.endSession('local-tab');
      expect(localService.killed, ['local_1']);
    },
  );

  test(
    'exec, MachineShell.local and ensureLocalAgentQuietly run without SSH',
    () async {
      final profile = localComputerProfile(name: 'This computer');
      await manager.startSession(
        profile,
        sessionId: 'local-exec',
        muxName: 'local_2',
        initialWidth: 80,
        initialHeight: 24,
        replayRemoteHistory: true,
      );

      final out = await manager.exec('local-exec', 'uname -s');
      expect(utf8.decode(out), 'Linux\n');

      final shellOut = await MachineShell.local(manager).exec('echo hi');
      expect(utf8.decode(shellOut), 'Linux\n');

      await manager.ensureLocalAgentQuietly();
      expect(localService.shellCommands, ['uname -s', 'echo hi']);
      expect(localService.ensureInstalledCalls, 2);
      expect(sshBackend.calls, isEmpty);
    },
  );

  test(
    'LocalAgentService.runShellCommand dispatches sh on POSIX and cmd on Windows',
    () async {
      final calls = <(String, List<String>)>[];
      final posix = LocalAgentService(
        operatingSystem: 'Linux',
        architecture: 'x86_64',
        runProcess: (exe, args) async {
          calls.add((exe, args));
          return ProcessResult(1, 0, 'Linux\n', '');
        },
      );
      expect(utf8.decode(await posix.runShellCommand('uname -s')), 'Linux\n');
      expect(calls.single.$1, 'sh');
      expect(calls.single.$2, ['-c', 'uname -s']);

      calls.clear();
      final win = LocalAgentService(
        operatingSystem: 'Windows',
        architecture: 'AMD64',
        runProcess: (exe, args) async {
          calls.add((exe, args));
          return ProcessResult(
            2,
            1,
            '',
            "'uname' is not recognized as an internal or external command.",
          );
        },
      );
      expect(
        utf8.decode(await win.runShellCommand('uname -s')),
        contains('is not recognized'),
      );
      expect(calls.single.$1, 'cmd');
      expect(calls.single.$2, ['/c', 'uname -s']);
    },
  );
}

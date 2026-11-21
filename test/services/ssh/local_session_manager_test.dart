import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/terminal/local_agent_service.dart';
import 'package:termphin/services/terminal/local_agent_transport.dart';
import 'package:termphin/services/terminal/terminal_text.dart';

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
  int listCalls = 0;

  @override
  bool get isWindows => windows;

  @override
  Future<String> ensureInstalled() async => windows
      ? r'C:\Users\alice\AppData\Local\termphin\bin\termphin-agent.exe'
      : '/home/alice/.local/lib/termphin/termphin-agent';

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
}

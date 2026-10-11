import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import 'package:termphin/models/remote_agent_status.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

class FakeSshBackend {
  final List<MethodCall> calls = [];
  final List<FakeSshService> services = [];
  Object? connectError;

  /// Which candidate address the fake transport reports having reached, when
  /// a test needs one other than the profile's first.
  String? reachedHost;
  Object? execError;
  Object? tunnelOpenError;
  Completer<void>? connectGate;
  Completer<void> connectCalled = Completer<void>();
  List<String> connectionMessages = const [];
  RemoteShellType remoteShellType = RemoteShellType.unix;
  String remoteSessionList = '';

  /// Answers `runWithResult` in place of the default clean exit - a hold to
  /// stall a command, a throw to fail it.
  Future<SSHRunResult> Function(String command)? runWithResult;

  /// What the agent writes as a shell attaches with [command], in place of
  /// the bare end-of-replay marker a `--replay` attach gets by default.
  List<int> Function(String command)? attachOutput;

  SshService createService() {
    final service = FakeSshService(this);
    services.add(service);
    return service;
  }

  FakeSshService get latestService => services.last;
}

class FakeSshService extends SshService {
  FakeSshService(this.backend) : fakeClient = FakeSshClient(backend);

  final FakeSshBackend backend;
  final FakeSshClient fakeClient;
  final StreamController<Uint8List> _output =
      StreamController<Uint8List>.broadcast();
  final FakeSshSession fakeSession = FakeSshSession();
  bool connected = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  SSHClient get client => fakeClient;

  @override
  bool get isAlive => connected && !fakeClient.isClosed;

  @override
  Future<void> connect(
    SshProfile profile, {
    void Function(String message)? onAuthMessage,
    void Function(String message)? onConnectionLog,
    HostKeyPrompt? onHostKeyPrompt,
    KeyboardInteractivePrompt? onKeyboardInteractive,
    int jumpDepth = 0,
  }) async {
    backend.calls.add(
      MethodCall('connect', {
        'host': profile.host,
        'port': profile.port,
        'username': profile.username,
      }),
    );
    if (!backend.connectCalled.isCompleted) {
      backend.connectCalled.complete();
    }
    for (final message in backend.connectionMessages) {
      onAuthMessage?.call(message);
    }
    final gate = backend.connectGate;
    if (gate != null) await gate.future;
    final error = backend.connectError;
    if (error != null) throw error;
    connectedHost = backend.reachedHost ?? profile.connectionCandidates.first;
    connected = true;
  }

  @override
  Future<RemoteShellType> detectRemoteShell() async => backend.remoteShellType;

  @override
  Future<SSHSession> startShell({
    int width = 80,
    int height = 24,
    String? command,
  }) async {
    backend.calls.add(
      MethodCall('startShell', {
        'width': width,
        'height': height,
        'command': command,
      }),
    );
    final scripted = backend.attachOutput;
    if (scripted != null && command != null) {
      emit(scripted(command));
    } else if (command?.contains(' --replay ') ?? false) {
      emit(utf8.encode('\x1b]5380;termphin-replay-end\x07'));
    }
    return fakeSession;
  }

  void emit(List<int> bytes) {
    if (!_output.isClosed) _output.add(Uint8List.fromList(bytes));
  }

  @override
  void write(Uint8List data) {
    backend.calls.add(MethodCall('write', {'data': Uint8List.fromList(data)}));
  }

  /// Receipts asked for and not yet answered, oldest first.
  final receipts = <Completer<void>>[];

  @override
  Future<void> confirmReceipt() {
    final receipt = Completer<void>();
    receipts.add(receipt);
    return receipt.future;
  }

  @override
  void resizeTerminal(int width, int height) {
    backend.calls.add(MethodCall('resize', {'width': width, 'height': height}));
  }

  @override
  Future<void> startLocalForward(
    String ruleId,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async {
    final error = backend.tunnelOpenError;
    if (error != null) throw error;
    backend.calls.add(
      MethodCall('tunnelOpen', {
        'ruleId': ruleId,
        'ruleType': 'local',
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
      }),
    );
  }

  @override
  Future<void> startRemoteForward(
    String ruleId,
    int remotePort,
    String localHost,
    int localPort,
  ) async {
    final error = backend.tunnelOpenError;
    if (error != null) throw error;
    backend.calls.add(
      MethodCall('tunnelOpen', {
        'ruleId': ruleId,
        'ruleType': 'remote',
        'localPort': localPort,
        'remotePort': remotePort,
        'localHost': localHost,
      }),
    );
  }

  @override
  void stopLocalForward(String ruleId) {
    backend.calls.add(
      MethodCall('tunnelClose', {'ruleId': ruleId, 'ruleType': 'local'}),
    );
  }

  @override
  void stopRemoteForward(String ruleId) {
    backend.calls.add(
      MethodCall('tunnelClose', {'ruleId': ruleId, 'ruleType': 'remote'}),
    );
  }

  /// What the last health check was started with, null before one was.
  bool? healthCheckResumable;
  int probes = 0;
  bool? lastProbeQuick;

  @override
  void startHealthCheck({bool foreground = true, bool resumable = false}) {
    healthCheckResumable = resumable;
  }

  @override
  void probeConnection({bool quick = false}) {
    probes++;
    lastProbeQuick = quick;
  }

  int latencyMeasurements = 0;

  @override
  void measureLatency() => latencyMeasurements++;

  @override
  void stopHealthCheck() {}

  @override
  Future<void> disconnect() async {
    if (!connected && fakeClient.isClosed) return;
    backend.calls.add(const MethodCall('disconnect'));
    connected = false;
    await fakeClient.close();
    fakeSession.close();
    if (!_output.isClosed) await _output.close();
  }
}

class FakeSshClient implements SSHClient {
  FakeSshClient(this.backend);

  final FakeSshBackend backend;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<Uint8List> run(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    backend.calls.add(MethodCall('exec', {'command': command}));
    final error = backend.execError;
    if (error != null) throw error;
    if (command.contains(' list')) {
      return Uint8List.fromList(utf8.encode(backend.remoteSessionList));
    }
    return Uint8List.fromList([7, 8]);
  }

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    backend.calls.add(MethodCall('runWithResult', {'command': command}));
    final answer = backend.runWithResult;
    if (answer != null) return answer(command);
    return SSHRunResult(
      output: Uint8List(0),
      stdout: Uint8List(0),
      stderr: Uint8List(0),
      exitCode: 0,
      exitSignal: null,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSshSession implements SSHSession {
  final Completer<void> _done = Completer<void>();

  /// Set to make [close] throw, the way dartssh2's own session does when
  /// the transport underneath it is already gone.
  Object? closeError;

  @override
  Future<void> get done => _done.future;

  @override
  void close() {
    final error = closeError;
    if (error != null) throw error;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRemoteAgentService extends RemoteAgentService {
  FakeRemoteAgentService(this.backend);

  final FakeSshBackend backend;
  RemoteAgentState state = RemoteAgentState.current;
  String remoteSha256 = 'a' * 64;
  bool supported = true;
  String remoteVersion = '0.0.9';

  DartRemoteAgentStatus get status => DartRemoteAgentStatus(
    home: supported ? '/home/test' : null,
    binaryPath: supported
        ? '/home/test/.local/lib/termphin/termphin-agent'
        : null,
    publicStatus: RemoteAgentStatus(
      state: supported ? state : RemoteAgentState.unsupported,
      supported: supported,
      architecture: 'x86_64',
      bundledVersion: '0.1.0',
      bundledSha256: 'a' * 64,
      bundledProtocol: 1,
      remoteVersion: remoteVersion,
      remoteSha256: remoteSha256,
      remoteProtocol: 1,
    ),
  );

  @override
  Future<DartRemoteAgentStatus> probe(SSHClient client) async {
    backend.calls.add(const MethodCall('probeAgent'));
    return status;
  }

  @override
  Future<DartRemoteAgentStatus> ensureForAttach(
    SSHClient client, {
    DartRemoteAgentStatus? probed,
  }) async {
    backend.calls.add(const MethodCall('ensureAgent'));
    return status;
  }

  @override
  Future<DartRemoteAgentStatus> install(
    SSHClient client, {
    DartRemoteAgentStatus? current,
  }) async {
    backend.calls.add(const MethodCall('installAgent'));
    state = RemoteAgentState.current;
    remoteSha256 = 'a' * 64;
    return status;
  }
}

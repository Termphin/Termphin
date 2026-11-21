import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/local_agent_transport.dart';

class _FakeSink implements IOSink {
  final List<List<int>> added = [];
  final Completer<void> _done = Completer<void>();
  bool closed = false;

  @override
  void add(List<int> data) {
    if (closed) throw StateError('Sink closed');
    added.add(List<int>.from(data));
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProcess implements Process {
  // ignore: close_sinks - fake in-memory sink closed in tests
  final _FakeSink fakeStdin = _FakeSink();
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>();
  final Completer<int> exitCompleter = Completer<int>();

  bool killed = false;
  ProcessSignal? killSignal;

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
    killed = true;
    killSignal = signal;
    if (!exitCompleter.isCompleted) {
      unawaited(stdoutController.close());
      unawaited(stderrController.close());
      exitCompleter.complete(-1);
    }
    return true;
  }

  @override
  int get pid => 4242;
}

void main() {
  test(
    'starts with the expected attach --stdio argv and forwards io',
    () async {
      String? launchedExecutable;
      List<String>? launchedArgs;
      final process = _FakeProcess();

      final transport = LocalAgentTransport(
        startProcess: (executable, arguments, workingDirectory) async {
          launchedExecutable = executable;
          launchedArgs = arguments;
          return process;
        },
      );

      final received = <String>[];
      final sub = transport.output.listen(
        (chunk) => received.add(utf8.decode(chunk)),
      );
      addTearDown(sub.cancel);

      await transport.start(
        binary: '/home/alice/.local/lib/termphin/termphin-agent',
        sessionName: 'work',
        columns: 120,
        rows: 40,
        device: 'dev-1;desktop;TGludXg',
      );

      expect(
        launchedExecutable,
        '/home/alice/.local/lib/termphin/termphin-agent',
      );
      expect(launchedArgs, [
        'attach',
        '--stdio',
        '120x40',
        '--replay',
        '--control',
        '--device',
        'dev-1;desktop;TGludXg',
        'work',
      ]);
      expect(transport.isAlive, isTrue);

      process.stdoutController.add(utf8.encode('hello'));
      await pumpEventQueue();
      expect(received, ['hello']);

      transport.write(Uint8List.fromList(utf8.encode('ls\n')));
      expect(process.fakeStdin.added.map(utf8.decode).toList(), ['ls\n']);

      await transport.disconnect();
    },
  );

  test('resizeTerminal writes the OSC 5386 size message to stdin', () async {
    final process = _FakeProcess();
    final transport = LocalAgentTransport(
      startProcess: (_, _, _) async => process,
    );

    await transport.start(
      binary: '/usr/bin/termphin-agent',
      sessionName: 'main',
      columns: 80,
      rows: 24,
    );

    transport.resizeTerminal(132, 43);
    transport.resizeTerminal(0, -5);

    expect(process.fakeStdin.added.map(utf8.decode).toList(), [
      '\x1b]5386;size;132;43\x07',
      '\x1b]5386;size;1;1\x07',
    ]);

    await transport.disconnect();
  });

  test(
    'disconnect closes stdin and kills after grace if still running',
    () async {
      final process = _FakeProcess();
      final transport = LocalAgentTransport(
        startProcess: (_, _, _) async => process,
        disconnectGrace: const Duration(milliseconds: 20),
      );
      var lostCalled = false;
      transport.onConnectionLost = () => lostCalled = true;

      await transport.start(
        binary: '/usr/bin/termphin-agent',
        sessionName: 'main',
        columns: 80,
        rows: 24,
      );

      await transport.disconnect();

      expect(process.fakeStdin.closed, isTrue);
      expect(process.killed, isTrue);
      expect(transport.isAlive, isFalse);
      expect(lostCalled, isFalse);
    },
  );

  test(
    'unexpected process exit flips isAlive and fires onConnectionLost',
    () async {
      final process = _FakeProcess();
      final transport = LocalAgentTransport(
        startProcess: (_, _, _) async => process,
      );
      var lostCount = 0;
      transport.onConnectionLost = () => lostCount++;

      await transport.start(
        binary: '/usr/bin/termphin-agent',
        sessionName: 'main',
        columns: 80,
        rows: 24,
      );

      process.stderrController.add(utf8.encode('boom\n'));
      await process.stdoutController.close();
      await process.stderrController.close();
      process.exitCompleter.complete(1);

      expect(await transport.exitCode, 1);
      expect(transport.isAlive, isFalse);
      expect(transport.stderrText, 'boom');
      expect(lostCount, 1);
    },
  );
}

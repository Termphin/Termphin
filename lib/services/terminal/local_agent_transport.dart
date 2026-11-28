import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'session_transport.dart';

/// Spawns the local agent process for a terminal transport, in
/// [workingDirectory] when given.
typedef LocalProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments,
      String? workingDirectory,
    );

/// Terminal transport backed by a local `termphin-agent attach --stdio`
/// process over plain pipes.
class LocalAgentTransport implements SessionTransport {
  LocalAgentTransport({
    LocalProcessStarter? startProcess,
    Duration disconnectGrace = const Duration(seconds: 2),
  }) : _startProcess = startProcess ?? _defaultStartProcess,
       _disconnectGrace = disconnectGrace;

  static Future<Process> _defaultStartProcess(
    String executable,
    List<String> arguments,
    String? workingDirectory,
  ) => Process.start(executable, arguments, workingDirectory: workingDirectory);

  /// Builds the argv passed to `termphin-agent` for a stdio attach session.
  static List<String> attachArguments({
    required String sessionName,
    required int columns,
    required int rows,
    bool replay = true,
    bool control = true,
    String? device,
  }) {
    final cols = math.max(1, columns);
    final height = math.max(1, rows);
    return [
      'attach',
      '--stdio',
      '${cols}x$height',
      if (replay) '--replay',
      if (control) '--control',
      if (device != null && device.isNotEmpty) ...['--device', device],
      sessionName,
    ];
  }

  static const _maxStderrBytes = 16 * 1024;

  final LocalProcessStarter _startProcess;
  final Duration _disconnectGrace;

  final StreamController<Uint8List> _outputController =
      StreamController<Uint8List>.broadcast();
  final Completer<int> _exitCompleter = Completer<int>();
  final BytesBuilder _stderr = BytesBuilder(copy: false);

  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Future<void>? _disconnectFuture;
  bool _exited = false;
  bool _disconnecting = false;
  bool _lostNotified = false;

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  bool get isAlive => _process != null && !_exited && !_disconnecting;

  @override
  void Function()? onConnectionLost;

  /// Completes with the attach client's exit code once the process exits and
  /// its output streams have drained.
  Future<int> get exitCode => _exitCompleter.future;

  /// Completes when the attach process has exited.
  Future<void> get done => _exitCompleter.future.then((_) {});

  /// Diagnostic output written to stderr by the attach process, if any.
  String get stderrText =>
      utf8.decode(_stderr.toBytes(), allowMalformed: true).trim();

  /// Spawns the local attach process and begins forwarding stdout and stderr.
  ///
  /// [workingDirectory] is where the process starts: a session that does
  /// not exist yet is created by it, and its shell opens there - the user's
  /// home, not wherever the app happened to be launched from.
  Future<void> start({
    required String binary,
    required String sessionName,
    required int columns,
    required int rows,
    bool replay = true,
    bool control = true,
    String? device,
    String? workingDirectory,
  }) async {
    if (_process != null) {
      throw StateError('LocalAgentTransport has already been started.');
    }
    final args = attachArguments(
      sessionName: sessionName,
      columns: columns,
      rows: rows,
      replay: replay,
      control: control,
      device: device,
    );
    final process = await _startProcess(binary, args, workingDirectory);
    _process = process;

    unawaited(process.stdin.done.then((_) {}, onError: (_) {}));

    final stdoutDone = Completer<void>();
    _stdoutSub = process.stdout.listen(
      (chunk) {
        if (chunk.isNotEmpty && !_outputController.isClosed) {
          _outputController.add(Uint8List.fromList(chunk));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_outputController.isClosed) {
          _outputController.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      cancelOnError: false,
    );

    final stderrDone = Completer<void>();
    _stderrSub = process.stderr.listen(
      (chunk) {
        if (_stderr.length < _maxStderrBytes) {
          final remaining = _maxStderrBytes - _stderr.length;
          _stderr.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
        }
      },
      onError: (_) {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      cancelOnError: false,
    );

    unawaited(_watchExit(process, stdoutDone.future, stderrDone.future));
  }

  Future<void> _watchExit(
    Process process,
    Future<void> stdoutDone,
    Future<void> stderrDone,
  ) async {
    int code;
    try {
      code = await process.exitCode;
    } catch (_) {
      code = -1;
    }
    try {
      await Future.wait([
        stdoutDone,
        stderrDone,
      ]).timeout(const Duration(milliseconds: 200));
    } catch (_) {}
    _exited = true;
    if (!_outputController.isClosed) {
      await _outputController.close();
    }
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(code);
    }
    if (!_disconnecting) {
      _notifyConnectionLost();
    }
  }

  void _notifyConnectionLost() {
    if (_lostNotified) return;
    _lostNotified = true;
    onConnectionLost?.call();
  }

  @override
  void write(Uint8List data) {
    final process = _process;
    if (process == null || _exited || _disconnecting || data.isEmpty) return;
    try {
      process.stdin.add(data);
    } catch (_) {
      _notifyConnectionLost();
    }
  }

  @override
  void resizeTerminal(int width, int height) {
    final cols = math.max(1, width);
    final rows = math.max(1, height);
    write(Uint8List.fromList(utf8.encode('\x1b]5386;size;$cols;$rows\x07')));
  }

  @override
  Future<void> disconnect() => _disconnectFuture ??= _performDisconnect();

  Future<void> _performDisconnect() async {
    _disconnecting = true;
    final process = _process;
    if (process == null) {
      if (!_outputController.isClosed) {
        await _outputController.close();
      }
      return;
    }

    try {
      unawaited(process.stdin.close().then((_) {}, onError: (_) {}));
    } catch (_) {}

    if (!_exited) {
      try {
        await _exitCompleter.future.timeout(_disconnectGrace);
      } catch (_) {
        try {
          process.kill();
        } catch (_) {}
        try {
          await _exitCompleter.future.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    }

    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;
    if (!_outputController.isClosed) {
      await _outputController.close();
    }
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(-1);
    }
  }
}

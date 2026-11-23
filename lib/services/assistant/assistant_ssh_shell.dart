import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../ssh/ssh_session_manager.dart';
import 'assistant_agent.dart';

/// Runs the assistant's commands in channels of their own on one session's
/// connection, beside the user's terminal.
class SessionAssistantShell implements AssistantShell {
  SessionAssistantShell(this._manager, this._sessionId);

  final SshSessionManager _manager;
  final String _sessionId;

  @override
  Future<AssistantRun> run(String command, {required Duration timeout}) =>
      _manager.runCommand(_sessionId, command, timeout: timeout);

  @override
  Future<AssistantPty> open(
    String command, {
    required int columns,
    required int rows,
  }) async => _SessionPty(
    await _manager.openPty(_sessionId, command, columns: columns, rows: rows),
  );
}

/// An approved command running with a terminal on the session's connection.
/// With a terminal the server sends everything on standard output; error
/// output is merged in all the same.
class _SessionPty implements AssistantPty {
  _SessionPty(this._session);

  final SSHSession _session;

  @override
  Stream<Uint8List> get output {
    final merged = StreamController<Uint8List>();
    var open = 2;
    void done() {
      if (--open == 0) unawaited(merged.close());
    }

    _session.stdout.listen(merged.add, onDone: done);
    _session.stderr.listen(merged.add, onDone: done);
    return merged.stream;
  }

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void resize(int columns, int rows) => _session.resizeTerminal(columns, rows);

  @override
  Future<int?> get exitCode async {
    await _session.done;
    return _session.exitCode;
  }

  @override
  void close() => _session.close();
}

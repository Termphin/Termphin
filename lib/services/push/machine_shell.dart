import 'dart:typed_data';

import '../ssh/ssh_session_manager.dart';

/// One way to run a command on a machine and read what it printed: over a
/// session's connection, or over one made only to set the machine up in the
/// background. [key] names the connection, so what is learned about the
/// machine through it - whether it is Windows - is asked once.
class MachineShell {
  MachineShell(this.key, this._exec);

  /// Through the connection of session [sessionId].
  factory MachineShell.session(SshSessionManager manager, String sessionId) =>
      MachineShell(sessionId, (command) => manager.exec(sessionId, command));

  final String key;
  final Future<Uint8List> Function(String command) _exec;

  Future<Uint8List> exec(String command) => _exec(command);
}

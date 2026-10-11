import 'dart:convert';
import 'dart:typed_data';

import '../../models/remote_shell.dart';
import '../ssh/ssh_session_manager.dart';
import 'snippet_runner.dart';

/// Runs a snippet in the session [sessionId] is attached to.
///
/// The staging half, when there is one, travels over an exec channel rather
/// than the terminal: it never appears on screen, is not subject to the
/// shell's line editing, and can carry a body of any size. Only the short
/// command that kicks it off is typed into the session, so the user sees
/// something they could plausibly have typed themselves.
///
/// Throws if staging fails, which is the caller's cue that the run never
/// started - as opposed to started and failed, which arrives later as a
/// completion marker.
Future<void> launchSnippet({
  required SshSessionManager manager,
  required String sessionId,
  required String command,
  required RemoteShellType shellType,
  String? runId,
}) async {
  final execution = prepareSnippetExecution(
    command: command,
    shellType: shellType,
    runId: runId,
  );
  final setup = execution.setupCommand;
  if (setup != null) {
    await manager.exec(sessionId, setup);
  }
  manager.sendInput(
    sessionId,
    Uint8List.fromList(utf8.encode(execution.terminalInput)),
  );
}

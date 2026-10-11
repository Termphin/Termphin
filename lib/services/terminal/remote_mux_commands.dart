import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../models/session_tab.dart';
import '../app/version_compare.dart';
import '../ssh/remote_agent_service.dart';
import 'osc_markers.dart';

/// Every command Termphin runs against the agent on the far end, and the
/// parsing of what comes back.
///
/// Split out of `SshSessionManager`, which was carrying the quoting rules for
/// two shells, a tab-separated output format and its own bookkeeping in the
/// same class. Nothing here touches a tab or a session: it takes a client and
/// a name and returns what the server said, which is what makes the Windows
/// quoting - the part that actually goes wrong - testable on its own.
class RemoteMuxCommands {
  const RemoteMuxCommands([this._agent = const RemoteAgentService()]);

  final RemoteAgentService _agent;

  /// The command a new shell is started with to attach to [name].
  ///
  /// `exec` and the args after it only exist as a single command line once
  /// it reaches a shell. On Windows that shell is cmd.exe or PowerShell,
  /// neither of which has an `exec` builtin, and neither of which uses POSIX
  /// single-quote escaping - see `remote_agent_service.dart`'s
  /// [windowsQuote].
  ///
  /// `&` is PowerShell's call operator, which a bare quoted path needs in
  /// order to run rather than echo. Only safe because
  /// [powerShellCommandLine] puts a PowerShell in front of it - cmd.exe reads
  /// a leading `&` as an error.
  ///
  /// [resumeFrom] asks the agent to continue from that output position instead
  /// of replaying, falling back to the replay when it cannot. Never on
  /// Windows: ConPTY re-renders what the shell wrote, so the bytes received
  /// are not the bytes the agent counted.
  String attachCommand(
    Multiplexer backend,
    String binary,
    String name,
    bool replayRemoteHistory, {
    String? operatingSystem,
    OutputPosition? resumeFrom,
  }) => switch (backend) {
    Multiplexer.termphin when operatingSystem == 'Windows' =>
      powerShellCommandLine(
        replayRemoteHistory
            ? '& ${windowsQuote(binary)} attach --replay ${windowsQuote(name)}'
            : '& ${windowsQuote(binary)} attach ${windowsQuote(name)}',
        interactive: true,
      ),
    Multiplexer.termphin => [
      'exec ${shellQuote(binary)} attach',
      if (replayRemoteHistory) '--replay',
      if (resumeFrom != null)
        '--resume ${resumeFrom.epoch}:${resumeFrom.offset}',
      shellQuote(name),
    ].join(' '),
    Multiplexer.none => '',
  };

  /// The first agent that takes `--resume`.
  static const resumeSinceVersion = '0.12.0';

  /// Whether an agent at [version] understands `--resume`. One that predates
  /// it reads the flag as the session name and fails the attach.
  static bool agentCanResume(String? version) {
    if (version == null || !isReleasedVersion(version)) return false;
    return compareVersions(version, resumeSinceVersion) >= 0;
  }

  /// The sessions [client]'s host is holding open, or an empty list when the
  /// agent is not usable there.
  ///
  /// An empty list from a host whose agent failed to probe means "could not
  /// ask", not "nothing there" - hence [DartRemoteAgentStatus.usable] being
  /// returned alongside, so the caller can tell those apart before acting on
  /// the absence of a session.
  Future<({List<RemoteMuxSession> sessions, DartRemoteAgentStatus agent})> list(
    SSHClient client,
  ) async {
    final agent = await _agent.probe(client);
    if (!agent.usable) {
      return (sessions: const <RemoteMuxSession>[], agent: agent);
    }
    final isWindows = agent.publicStatus.operatingSystem == 'Windows';
    final output = await client.run(
      isWindows
          ? powerShellCommandLine('& ${windowsQuote(agent.binaryPath!)} list')
          : '${shellQuote(agent.binaryPath!)} list',
    );
    return (
      sessions: parseSessionList(
        utf8.decode(output, allowMalformed: true),
        Multiplexer.termphin,
      ),
      agent: agent,
    );
  }

  /// Ends [name] on the server. [binary] is the agent an attached session
  /// already runs, which spares the probe; without it the agent is probed
  /// but never installed or updated - a session about to be gone is no
  /// reason to wait on an upload, and the binary that started it is the one
  /// that knows how to stop it.
  Future<void> kill(
    SSHClient client,
    String name,
    Multiplexer backend, {
    ({String path, bool isWindows})? binary,
  }) async {
    binary ??= await _installedBinaryFor(client, backend);
    final result = await client.runWithResult(
      binary.isWindows
          ? powerShellCommandLine(
              '& ${windowsQuote(binary.path)} kill ${windowsQuote(name)}',
            )
          : '${shellQuote(binary.path)} kill ${shellQuote(name)}',
    );
    throwOnCommandFailure(result, 'Failed to end the remote session.');
  }

  Future<void> rename(
    SSHClient client,
    String oldName,
    String newName,
    Multiplexer backend,
  ) async {
    final binary = await _binaryFor(client, backend);
    final result = await client.runWithResult(
      binary.isWindows
          ? powerShellCommandLine(
              '& ${windowsQuote(binary.path)} rename '
              '${windowsQuote(oldName)} ${windowsQuote(newName)}',
            )
          : '${shellQuote(binary.path)} rename ${shellQuote(oldName)} '
                '${shellQuote(newName)}',
    );
    throwOnCommandFailure(result, 'Failed to rename the remote session.');
  }

  /// [RemoteAgentService.ensureForAttach] rather than a plain probe: a rename
  /// runs over its own short-lived connection, never through
  /// `startSession`'s attach path, which is where a pending update would
  /// otherwise be installed. A probe-only check here would run every one of
  /// them against whatever stale binary happens to be on the server.
  Future<({String path, bool isWindows})> _binaryFor(
    SSHClient client,
    Multiplexer backend, {
    DartRemoteAgentStatus? probed,
  }) async {
    if (backend == Multiplexer.none) {
      throw Exception('Session is not persistent.');
    }
    final status = await _agent.ensureForAttach(client, probed: probed);
    final path = status.binaryPath;
    if (path == null) throw Exception('Termphin helper is not installed.');
    return (
      path: path,
      isWindows: status.publicStatus.operatingSystem == 'Windows',
    );
  }

  /// The agent already on the host, falling back to [_binaryFor] only when
  /// there is none to use.
  Future<({String path, bool isWindows})> _installedBinaryFor(
    SSHClient client,
    Multiplexer backend,
  ) async {
    if (backend == Multiplexer.none) {
      throw Exception('Session is not persistent.');
    }
    final status = await _agent.probe(client);
    if (!status.usable) return _binaryFor(client, backend, probed: status);
    return (
      path: status.binaryPath!,
      isWindows: status.publicStatus.operatingSystem == 'Windows',
    );
  }

  /// Tab-separated: name, window count, creation timestamp, attached flag.
  /// A line that does not carry all four is skipped rather than guessed at -
  /// a shell profile that prints a banner writes into this stream too.
  List<RemoteMuxSession> parseSessionList(String output, Multiplexer backend) =>
      output
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => line.split('\t'))
          .where((parts) => parts.length >= 4)
          .map(
            (parts) => RemoteMuxSession.fromMap({
              'name': parts[0],
              'windows': int.tryParse(parts[1]) ?? 1,
              'createdAt': int.tryParse(parts[2]) ?? 0,
              'attached': (int.tryParse(parts[3]) ?? 0) > 0,
              'multiplexer': backend.name,
            }),
          )
          .toList();

  void validateMuxName(String name) {
    if (SessionTab.validateName(name) != null) {
      throw Exception('Session name contains unsupported characters.');
    }
  }

  /// `run()` never throws on a nonzero exit, so this is what turns a failed
  /// command into one. The server's own stderr is a better message than
  /// anything written here, when there is any.
  void throwOnCommandFailure(SSHRunResult result, String fallback) {
    if (result.exitCode == null || result.exitCode == 0) return;
    final message = utf8.decode(result.stderr, allowMalformed: true).trim();
    throw Exception(message.isEmpty ? fallback : message);
  }
}

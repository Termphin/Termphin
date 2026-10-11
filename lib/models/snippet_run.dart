/// Where one host has got to in a snippet run.
enum SnippetRunStatus {
  /// Queued, waiting for its turn to connect.
  pending,

  /// Opening the SSH connection and attaching the run's session.
  connecting,

  /// Command sent; waiting for the completion marker.
  running,

  /// Marker seen with exit code 0.
  succeeded,

  /// Marker seen with a non-zero exit code.
  failed,

  /// Never got as far as reporting a status - connect or auth blew up.
  error;

  bool get isTerminal => this == succeeded || this == failed || this == error;
}

/// One host's slice of a snippet run.
///
/// [sessionId] names a throwaway session that lives only as long as the
/// command does. What the host said is copied into [output] as it arrives, so
/// the record still reads once that session is gone - the runs screen is a
/// history of finished work, not a way back into a shell.
class SnippetRun {
  const SnippetRun({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.sessionId,
    this.status = SnippetRunStatus.pending,
    this.exitCode,
    this.error,
    this.output = '',
    this.finishedAt,
  });

  final String id;
  final String profileId;
  final String profileName;
  final String sessionId;
  final SnippetRunStatus status;

  /// Exit code reported by the completion marker, once one arrives.
  final int? exitCode;

  /// Why the run never started, for [SnippetRunStatus.error].
  final String? error;

  /// Everything the host printed, with escape sequences stripped.
  final String output;
  final DateTime? finishedAt;

  SnippetRun copyWith({
    SnippetRunStatus? status,
    int? exitCode,
    String? error,
    String? output,
    DateTime? finishedAt,
  }) => SnippetRun(
    id: id,
    profileId: profileId,
    profileName: profileName,
    sessionId: sessionId,
    status: status ?? this.status,
    exitCode: exitCode ?? this.exitCode,
    error: error ?? this.error,
    output: output ?? this.output,
    finishedAt: finishedAt ?? this.finishedAt,
  );
}

/// One "run this snippet on these hosts" action.
class SnippetRunBatch {
  const SnippetRunBatch({
    required this.id,
    required this.snippetName,
    required this.command,
    required this.startedAt,
    required this.runs,
  });

  final String id;
  final String snippetName;

  /// The command as sent, with `{{placeholders}}` already filled in.
  final String command;
  final DateTime startedAt;
  final List<SnippetRun> runs;

  bool get isFinished => runs.every((run) => run.status.isTerminal);
  int get succeededCount =>
      runs.where((run) => run.status == SnippetRunStatus.succeeded).length;
  int get failedCount => runs
      .where(
        (run) =>
            run.status == SnippetRunStatus.failed ||
            run.status == SnippetRunStatus.error,
      )
      .length;

  SnippetRunBatch withRun(SnippetRun run) => SnippetRunBatch(
    id: id,
    snippetName: snippetName,
    command: command,
    startedAt: startedAt,
    runs: [
      for (final existing in runs)
        if (existing.id == run.id) run else existing,
    ],
  );
}

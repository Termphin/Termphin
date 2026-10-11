import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/snippet.dart';
import '../models/snippet_run.dart';
import '../models/ssh_profile.dart';
import '../services/snippets/snippet_launcher.dart';
import '../services/ssh/ssh_session_manager.dart';
import '../services/terminal/terminal_text.dart';
import 'ssh_session_manager_provider.dart';

/// Batches of snippet runs, newest first.
///
/// A run owns a throwaway session that is torn down the moment it reports its
/// exit code, so nothing is left running on a host and nothing shows up in the
/// tab bar. What the host printed is copied into the run record on the way
/// past, which is what the runs screen reads back.
///
/// Batches are held in memory only: the sessions behind them are gone, so a
/// batch reloaded from a previous launch could never learn anything new.
class SnippetRunsNotifier extends Notifier<List<SnippetRunBatch>> {
  static const _uuid = Uuid();

  SshSessionManager get _manager => ref.read(sshSessionManagerProvider);
  late final void Function(String, int) _listener;

  /// Raw bytes seen per run, kept raw so a multi-byte character or escape
  /// sequence split across two reads is never decoded half-finished.
  final Map<String, BytesBuilder> _rawOutput = {};
  final Map<String, StreamSubscription<Uint8List>> _outputSubscriptions = {};

  /// Enough for any run worth reading back; a run that produces more than
  /// this wants a real terminal, not a history entry.
  static const _maxOutputBytes = 256 * 1024;

  /// A run's tail-flush waits out the last of the output, which can outlive
  /// the provider if the app moves on in between.
  bool _disposed = false;

  @override
  List<SnippetRunBatch> build() {
    _disposed = false;
    _listener = _onRunFinished;
    final manager = _manager;
    manager.addSnippetRunListener(_listener);
    ref.onDispose(() {
      _disposed = true;
      manager.removeSnippetRunListener(_listener);
      for (final subscription in _outputSubscriptions.values) {
        unawaited(subscription.cancel());
      }
      _outputSubscriptions.clear();
    });
    return const [];
  }

  /// Registers a batch running [snippet] on every profile in [profiles] and
  /// returns its id straight away, before a single host has been dialled.
  ///
  /// The caller opens the run window on that id, so the batch has to exist the
  /// moment the button is tapped: connecting first would leave the user on a
  /// dead sheet for as long as the slowest login takes. Every run starts out
  /// [SnippetRunStatus.pending] and moves on from there in the background.
  ///
  /// Hosts are connected one after another rather than all at once: each
  /// connect may install the remote helper and each run gets its own session,
  /// and a burst of simultaneous logins is both slower per host and more
  /// likely to trip rate limits.
  String start({
    required Snippet snippet,
    required List<SshProfile> profiles,
    Map<String, String> argValues = const {},
  }) {
    final batchId = _uuid.v4();
    final command = snippet.interpolate(argValues);
    final batch = SnippetRunBatch(
      id: batchId,
      snippetName: snippet.name,
      command: command,
      startedAt: DateTime.now(),
      runs: [
        for (final profile in profiles)
          SnippetRun(
            id: _uuid.v4(),
            profileId: profile.id,
            profileName: profile.name,
            sessionId: _uuid.v4(),
          ),
      ],
    );
    state = [batch, ...state];
    unawaited(_startAll(batchId, profiles, command));
    return batchId;
  }

  /// Stops dialling the hosts that are left once the batch is gone, since
  /// [forget] removes any reason to keep going.
  Future<void> _startAll(
    String batchId,
    List<SshProfile> profiles,
    String command,
  ) async {
    for (final profile in profiles) {
      if (_disposed || _batch(batchId) == null) return;
      final run = _batch(
        batchId,
      )?.runs.firstWhere((r) => r.profileId == profile.id);
      if (run == null) continue;
      await _startOne(batchId, run, profile, command);
    }
  }

  Future<void> _startOne(
    String batchId,
    SnippetRun run,
    SshProfile profile,
    String command,
  ) async {
    _update(batchId, run.copyWith(status: SnippetRunStatus.connecting));
    try {
      final session = await _manager.startSession(
        profile,
        sessionId: run.sessionId,
        isRun: true,
      );
      _watchOutput(batchId, run.id, run.sessionId);
      await launchSnippet(
        manager: _manager,
        sessionId: run.sessionId,
        command: command,
        shellType: session.remoteShellType,
        runId: run.id,
      );
      _update(batchId, run.copyWith(status: SnippetRunStatus.running));
    } catch (error) {
      _update(
        batchId,
        run.copyWith(
          status: SnippetRunStatus.error,
          error: error.toString().replaceFirst('Exception: ', ''),
          finishedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Copies the session's output into the run record as it arrives, so the
  /// history still reads once the session behind it is gone. Over the size
  /// cap, only the tail is kept: `takeBytes` empties the builder, so it goes
  /// straight back in.
  void _watchOutput(String batchId, String runId, String sessionId) {
    final session = _manager.getSession(sessionId);
    if (session == null) return;
    final buffer = _rawOutput[runId] = BytesBuilder();
    _outputSubscriptions[runId] = session.outputStream.listen((bytes) {
      buffer.add(bytes);
      if (buffer.length > _maxOutputBytes) {
        final kept = buffer.takeBytes();
        buffer.add(Uint8List.sublistView(kept, kept.length - _maxOutputBytes));
      }
      _updateOutput(batchId, runId, buffer);
    });
  }

  /// `allowMalformed` covers the character the size cap above may have cut
  /// in half.
  void _updateOutput(String batchId, String runId, BytesBuilder buffer) {
    if (_disposed) return;
    final decoded = const Utf8Decoder(
      allowMalformed: true,
    ).convert(buffer.toBytes());
    final text = stripAnsi(decoded).trimRight();
    final run = _run(batchId, runId);
    if (run == null || run.output == text) return;
    _update(batchId, run.copyWith(output: text));
  }

  /// Markers replay with a session's scrollback, so a run that already
  /// reported must not be reopened by its own echo.
  void _onRunFinished(String runId, int exitCode) {
    for (final batch in state) {
      for (final run in batch.runs) {
        if (run.id != runId) continue;
        if (run.status.isTerminal) return;
        _update(
          batch.id,
          run.copyWith(
            status: exitCode == 0
                ? SnippetRunStatus.succeeded
                : SnippetRunStatus.failed,
            exitCode: exitCode,
            finishedAt: DateTime.now(),
          ),
        );
        unawaited(_finish(batch.id, run));
        return;
      }
    }
  }

  /// Flushes whatever the host said last and drops the session with it. The
  /// marker is the end of the run, and the session existed only to carry it.
  /// The delay gives the last of the output, which can still be in flight
  /// behind the marker, time to arrive.
  Future<void> _finish(String batchId, SnippetRun run) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final buffer = _rawOutput.remove(run.id);
    if (buffer != null) _updateOutput(batchId, run.id, buffer);
    await _outputSubscriptions.remove(run.id)?.cancel();
    if (_disposed) return;
    await _manager.endRunSession(run.sessionId);
  }

  SnippetRunBatch? _batch(String batchId) {
    for (final batch in state) {
      if (batch.id == batchId) return batch;
    }
    return null;
  }

  SnippetRun? _run(String batchId, String runId) {
    for (final run in _batch(batchId)?.runs ?? const <SnippetRun>[]) {
      if (run.id == runId) return run;
    }
    return null;
  }

  void _update(String batchId, SnippetRun run) {
    state = [
      for (final batch in state)
        if (batch.id == batchId) batch.withRun(run) else batch,
    ];
  }

  /// Drops [batchId] from the history, closing any session it still has open.
  /// A run's session exists only to carry that run's output back here, so once
  /// the record is gone there is nothing left for it to do.
  void forget(String batchId) {
    final batch = _batch(batchId);
    state = [
      for (final existing in state)
        if (existing.id != batchId) existing,
    ];
    for (final run in batch?.runs ?? const <SnippetRun>[]) {
      _rawOutput.remove(run.id);
      unawaited(_outputSubscriptions.remove(run.id)?.cancel());
      if (_manager.hasSession(run.sessionId)) {
        unawaited(_manager.endRunSession(run.sessionId));
      }
    }
  }

  /// Empties the history. Each batch still goes through [forget], so no
  /// session is left behind by the shortcut.
  void forgetAll() {
    for (final batch in [...state]) {
      forget(batch.id);
    }
  }
}

final snippetRunsProvider =
    NotifierProvider<SnippetRunsNotifier, List<SnippetRunBatch>>(
      SnippetRunsNotifier.new,
    );

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cancel_token.dart';
import 'download_service.dart';

enum TransferJobKind { upload, download, copy, move }

enum TransferJobState { queued, running, done, failed, cancelled }

/// One entry in a [TransferQueue]: what it is, how far it got and how it
/// ended. The work itself is the closure handed to [TransferQueue.add].
class TransferJob {
  TransferJob._(
    this._queue, {
    required this.id,
    required this.kind,
    required String label,
    required this.cancellable,
    required this.waited,
    required Future<Object?> Function(TransferJob job) run,
  }) : _run = run,
       _progress = TransferProgress(label: label);

  final TransferQueue _queue;
  final int id;
  final TransferJobKind kind;

  /// False for a copy or move once it runs: stopping `cp` halfway leaves half
  /// a folder. Such a job can still be taken off the queue before it starts.
  final bool cancellable;

  /// Whether another job was still in the queue when this one was added, so
  /// it started later than the moment it was asked for.
  final bool waited;

  final CancelToken cancel = CancelToken();
  final Future<Object?> Function(TransferJob job) _run;
  final Completer<Object?> _completer = Completer<Object?>();

  TransferJobState _state = TransferJobState.queued;
  TransferProgress _progress;
  Object? _error;

  TransferJobState get state => _state;
  TransferProgress get progress => _progress;

  /// Why a failed job failed.
  Object? get error => _error;

  bool get isFinished => switch (_state) {
    TransferJobState.done ||
    TransferJobState.failed ||
    TransferJobState.cancelled => true,
    _ => false,
  };

  bool get canCancel =>
      !cancel.isCancelled &&
      (_state == TransferJobState.queued ||
          (_state == TransferJobState.running && cancellable));

  /// Running, but asked to stop and still unwinding.
  bool get isCancelling =>
      _state == TransferJobState.running && cancel.isCancelled;

  /// Called by the work as it moves; ignored once the job has ended, so a
  /// late callback from an unwinding transfer cannot revive it on screen.
  void report(TransferProgress progress) {
    if (isFinished) return;
    _progress = progress;
    _queue._changed();
  }
}

/// The transfers of one session, run one at a time in the order they were
/// asked for.
///
/// One at a time because they share a connection: two at once only split its
/// bandwidth, and every question about overwriting is settled before a job
/// is added, so nothing waiting here can block on the user.
///
/// A job that ends well or is cancelled leaves the list at once - the caller
/// says so in a notification. A failed one stays until [clearFinished], since
/// that is the only place left to read why.
class TransferQueue extends ChangeNotifier {
  final List<TransferJob> _jobs = [];
  var _nextId = 0;
  var _pumping = false;
  var _disposed = false;

  /// Jobs added since the queue was last idle, and how many of them have
  /// ended - "2 of 5" counts within this run, not over the session's life.
  var _runSize = 0;
  var _runFinished = 0;

  List<TransferJob> get jobs => List.unmodifiable(_jobs);

  TransferJob? get running {
    for (final job in _jobs) {
      if (job.state == TransferJobState.running) return job;
    }
    return null;
  }

  bool get isBusy => _jobs.any((job) => !job.isFinished);

  bool get hasFailures => _jobs.any((j) => j.state == TransferJobState.failed);

  int get runSize => _runSize;

  /// 1-based position of the job in flight within the current run.
  int get runPosition => (_runFinished + 1).clamp(1, _runSize);

  /// Progress across the current run: every ended job counts as whole, the
  /// running one by its own fraction. Null while the running job cannot tell.
  double? get overallFraction {
    if (_runSize == 0) return null;
    final current = running;
    if (current == null) return _runFinished / _runSize;
    final fraction = current.progress.fraction;
    if (fraction == null) return _runSize == 1 ? null : _runFinished / _runSize;
    return ((_runFinished + fraction) / _runSize).clamp(0.0, 1.0);
  }

  /// Queues [run] and completes with what it returns once it has run.
  ///
  /// Fails with [TransferCancelled] when the job is cancelled, whether it was
  /// running or still waiting, and with the work's own error when it fails.
  Future<T> add<T>({
    required TransferJobKind kind,
    required String label,
    bool cancellable = true,
    required Future<T> Function(TransferJob job) run,
  }) {
    if (_disposed) return Future.error(const TransferCancelled());
    if (!isBusy) {
      _runSize = 0;
      _runFinished = 0;
    }
    final job = TransferJob._(
      this,
      id: _nextId++,
      kind: kind,
      label: label,
      cancellable: cancellable,
      waited: isBusy,
      run: run,
    );
    _jobs.add(job);
    _runSize++;
    notifyListeners();
    unawaited(_pump());
    return job._completer.future.then((value) => value as T);
  }

  /// A waiting job ends on the spot. A running one has its token tripped and
  /// reads as [TransferJob.isCancelling] until it unwinds; the next job waits
  /// for that, so two never share the connection.
  void cancel(TransferJob job) {
    if (!job.canCancel) return;
    job.cancel.cancel();
    if (job.state == TransferJobState.queued) {
      _finish(
        job,
        TransferJobState.cancelled,
        error: const TransferCancelled(),
      );
    }
    notifyListeners();
  }

  void clearFinished() {
    _jobs.removeWhere((job) => job.isFinished);
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (!_disposed) {
      final next = _nextQueued();
      if (next == null) break;
      next._state = TransferJobState.running;
      notifyListeners();
      try {
        final result = await next._run(next);
        if (next.cancel.isCancelled) {
          _finish(
            next,
            TransferJobState.cancelled,
            error: const TransferCancelled(),
          );
        } else {
          _finish(next, TransferJobState.done, result: result);
        }
      } catch (error, stackTrace) {
        final cancelled = next.cancel.isCancelled || error is TransferCancelled;
        _finish(
          next,
          cancelled ? TransferJobState.cancelled : TransferJobState.failed,
          error: cancelled ? const TransferCancelled() : error,
          stackTrace: stackTrace,
        );
      }
      if (!_disposed) notifyListeners();
    }
    _pumping = false;
  }

  TransferJob? _nextQueued() {
    for (final job in _jobs) {
      if (job.state == TransferJobState.queued) return job;
    }
    return null;
  }

  void _finish(
    TransferJob job,
    TransferJobState state, {
    Object? result,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (job._completer.isCompleted) return;
    job._state = state;
    job._error = state == TransferJobState.failed ? error : null;
    _runFinished++;
    if (state != TransferJobState.failed) _jobs.remove(job);
    if (error != null) {
      job._completer.completeError(error, stackTrace);
    } else {
      job._completer.complete(result);
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Cancels everything still waiting or running: the session the jobs
  /// belong to is going away.
  @override
  void dispose() {
    _disposed = true;
    for (final job in [..._jobs]) {
      if (job.isFinished) continue;
      job.cancel.cancel();
      _finish(
        job,
        TransferJobState.cancelled,
        error: const TransferCancelled(),
      );
    }
    super.dispose();
  }
}

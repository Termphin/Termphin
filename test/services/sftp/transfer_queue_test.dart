import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/download_service.dart';
import 'package:termphin/services/sftp/transfer_queue.dart';

/// Work that runs until the test lets it finish, or until it is cancelled.
class _Gate {
  final Completer<String> _done = Completer<String>();
  var started = false;

  Future<String> run(TransferJob job) {
    started = true;
    return job.cancel.race(_done.future);
  }

  void finish([String value = 'ok']) => _done.complete(value);

  void fail(Object error) => _done.completeError(error);
}

void main() {
  late TransferQueue queue;

  setUp(() => queue = TransferQueue());
  tearDown(() => queue.dispose());

  Future<String> add(
    _Gate gate, {
    String label = 'file',
    bool cancellable = true,
  }) => queue.add(
    kind: TransferJobKind.upload,
    label: label,
    cancellable: cancellable,
    run: gate.run,
  );

  test('runs jobs one at a time, in the order they were added', () async {
    final first = _Gate();
    final second = _Gate();
    final a = add(first);
    final b = add(second);
    await pumpEventQueue();

    expect(first.started, isTrue);
    expect(second.started, isFalse);
    expect(queue.jobs.map((j) => j.state), [
      TransferJobState.running,
      TransferJobState.queued,
    ]);

    first.finish('a');
    expect(await a, 'a');
    await pumpEventQueue();
    expect(second.started, isTrue);

    second.finish('b');
    expect(await b, 'b');
    expect(queue.isBusy, isFalse);
  });

  test('marks a job that joined a busy queue as having waited', () async {
    final first = _Gate();
    final second = _Gate();
    add(first).ignore();
    add(second).ignore();

    expect(queue.jobs.first.waited, isFalse);
    expect(queue.jobs.last.waited, isTrue);
    first.finish();
    second.finish();
  });

  test('one failure does not stop the jobs behind it', () async {
    final first = _Gate();
    final second = _Gate();
    final a = add(first);
    final b = add(second);
    await pumpEventQueue();

    first.fail(Exception('sftp.errors.diskFull'));
    await expectLater(a, throwsA(isA<Exception>()));
    await pumpEventQueue();
    second.finish();

    expect(await b, 'ok');
    expect(queue.jobs.single.state, TransferJobState.failed);
    expect(queue.jobs.single.error.toString(), contains('diskFull'));
  });

  test('cancelling a waiting job ends it without ever running it', () async {
    final first = _Gate();
    final second = _Gate();
    add(first).ignore();
    final b = add(second);
    await pumpEventQueue();

    queue.cancel(queue.jobs.last);
    await expectLater(b, throwsA(isA<TransferCancelled>()));
    first.finish();
    await pumpEventQueue();

    expect(second.started, isFalse);
    expect(queue.jobs, isEmpty);
  });

  test(
    'cancelling a running job holds the next one until it unwinds',
    () async {
      final first = _Gate();
      final second = _Gate();
      final a = add(first);
      add(second).ignore();
      await pumpEventQueue();

      final running = queue.jobs.first;
      queue.cancel(running);
      expect(running.isCancelling, isTrue);
      expect(running.canCancel, isFalse);

      await expectLater(a, throwsA(isA<TransferCancelled>()));
      await pumpEventQueue();
      expect(running.state, TransferJobState.cancelled);
      expect(queue.jobs, isNot(contains(running)));
      expect(second.started, isTrue);
      second.finish();
    },
  );

  test('a job that cannot be cancelled once running keeps going', () async {
    final first = _Gate();
    final a = add(first, cancellable: false);
    await pumpEventQueue();

    queue.cancel(queue.jobs.single);
    expect(queue.jobs.single.cancel.isCancelled, isFalse);
    first.finish();
    expect(await a, 'ok');
  });

  test('progress is ignored once a job has ended', () async {
    final gate = _Gate();
    final a = add(gate);
    await pumpEventQueue();
    final job = queue.jobs.single;
    gate.finish();
    await a;

    job.report(const TransferProgress(label: 'late', fraction: 0.1));
    expect(job.progress.label, 'file');
  });

  test('overall progress counts ended jobs whole', () async {
    final first = _Gate();
    final second = _Gate();
    final a = add(first);
    add(second).ignore();
    await pumpEventQueue();

    queue.jobs.first.report(
      const TransferProgress(label: 'file', fraction: 0.5),
    );
    expect(queue.overallFraction, 0.25);
    expect(queue.runPosition, 1);
    expect(queue.runSize, 2);

    first.finish();
    await a;
    await pumpEventQueue();
    queue.jobs.last.report(
      const TransferProgress(label: 'file', fraction: 0.5),
    );
    expect(queue.overallFraction, 0.75);
    expect(queue.runPosition, 2);
    second.finish();
  });

  test('a new run starts counting from one', () async {
    final first = _Gate();
    final a = add(first);
    first.finish();
    await a;
    await pumpEventQueue();

    final second = _Gate();
    add(second).ignore();
    expect(queue.runSize, 1);
    expect(queue.runPosition, 1);
    second.finish();
  });

  test('done and cancelled jobs leave the list, failed ones stay', () async {
    final done = _Gate();
    final failed = _Gate();
    final a = add(done);
    final b = add(failed);
    await pumpEventQueue();
    done.finish();
    await a;
    await pumpEventQueue();
    failed.fail(Exception('boom'));
    await expectLater(b, throwsA(isA<Exception>()));

    expect(queue.jobs.map((j) => j.state), [TransferJobState.failed]);
    expect(queue.hasFailures, isTrue);
    queue.clearFinished();
    expect(queue.jobs, isEmpty);
  });

  test('disposing cancels everything still waiting or running', () async {
    final local = TransferQueue();
    final first = _Gate();
    final second = _Gate();
    final a = local.add(
      kind: TransferJobKind.download,
      label: 'a',
      run: first.run,
    );
    final b = local.add(
      kind: TransferJobKind.download,
      label: 'b',
      run: second.run,
    );
    await pumpEventQueue();

    local.dispose();
    await expectLater(a, throwsA(isA<TransferCancelled>()));
    await expectLater(b, throwsA(isA<TransferCancelled>()));
    expect(second.started, isFalse);
  });
}

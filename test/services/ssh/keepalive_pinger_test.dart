import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/connection_quality.dart';
import 'package:termphin/services/ssh/keepalive_pinger.dart';

void main() {
  late FakeAsync async;
  late List<Completer<void>> pings;
  late ConnectionQuality quality;
  late KeepalivePinger pinger;
  var alive = true;
  var resumable = false;
  var lost = 0;
  LinkLoss? cause;

  int now() => async.elapsed.inMilliseconds;

  void run(void Function() body) {
    fakeAsync((a) {
      async = a;
      pings = [];
      alive = true;
      resumable = false;
      lost = 0;
      cause = null;
      quality = ConnectionQuality(clock: now);
      pinger = KeepalivePinger(
        ping: () {
          final c = Completer<void>();
          pings.add(c);
          return c.future;
        },
        isAlive: () => alive,
        resumable: () => resumable,
        quality: quality,
        onLost: (reason) {
          lost++;
          cause = reason;
        },
        clock: now,
      );
      body();
      pinger.stop();
    });
  }

  test('times each round trip', () {
    run(() {
      pinger.start(foreground: true);
      async.elapse(KeepalivePinger.foregroundInterval);
      async.elapse(const Duration(milliseconds: 120));
      pings.single.complete();
      async.flushMicrotasks();

      expect(quality.samples, [120]);
    });
  });

  test('never has two pings out at once', () {
    run(() {
      pinger.start(foreground: true);
      async.elapse(KeepalivePinger.foregroundInterval * 4);

      expect(pings, hasLength(1));
    });
  });

  test('a stuck ping shows as unresponsive before the link is given up', () {
    run(() {
      pinger.start(foreground: true);
      async.elapse(KeepalivePinger.foregroundInterval * 3);

      expect(quality.health, ConnectionHealth.unresponsive);
      expect(lost, 0);
    });
  });

  test('gives up after the silence limit', () {
    run(() {
      pinger.start(foreground: true);
      async.elapse(
        KeepalivePinger.lostAfter + KeepalivePinger.foregroundInterval,
      );

      expect(lost, 1);
      expect(cause, LinkLoss.silent);
      expect(pinger.isRunning, isFalse);
    });
  });

  test('loses the link at once when the client is gone', () {
    run(() {
      alive = false;
      pinger.start(foreground: true);
      async.elapse(KeepalivePinger.foregroundInterval);

      expect(lost, 1);
      expect(cause, LinkLoss.closed);
    });
  });

  test('pings less often in the background', () {
    run(() {
      pinger.start(foreground: false);
      async.elapse(KeepalivePinger.foregroundInterval * 2);
      expect(pings, isEmpty);

      async.elapse(KeepalivePinger.backgroundInterval);
      expect(pings, hasLength(1));
    });
  });

  test('a reply from before a restart is not timed', () {
    run(() {
      pinger.start(foreground: true);
      async.elapse(KeepalivePinger.foregroundInterval);
      pinger.start(foreground: true);
      pings.single.complete();
      async.flushMicrotasks();

      expect(quality.samples, isEmpty);
    });
  });

  /// Answers every ping that comes due over [ticks] intervals after
  /// [roundTrip].
  void answerPings(int ticks, Duration roundTrip) {
    for (var i = 0; i < ticks; i++) {
      async.elapse(
        KeepalivePinger.foregroundInterval -
            (i == 0 ? Duration.zero : roundTrip),
      );
      async.elapse(roundTrip);
      pings.last.complete();
      async.flushMicrotasks();
    }
  }

  /// How long after the last reply the link is given up on.
  Duration silenceUntilLost() {
    final start = async.elapsed;
    while (lost == 0 && async.elapsed - start < const Duration(minutes: 2)) {
      async.elapse(const Duration(seconds: 1));
    }
    return async.elapsed - start;
  }

  group('a session the server keeps alive', () {
    test('on a quick link is given up well before the old limit', () {
      run(() {
        resumable = true;
        pinger.start(foreground: true);
        answerPings(5, const Duration(milliseconds: 40));

        final silence = silenceUntilLost();

        expect(silence, greaterThanOrEqualTo(const Duration(seconds: 15)));
        expect(silence, lessThanOrEqualTo(const Duration(seconds: 20)));
      });
    });

    test('on a slow link is given longer', () {
      run(() {
        resumable = true;
        pinger.start(foreground: true);
        answerPings(5, const Duration(milliseconds: 900));

        final silence = silenceUntilLost();

        expect(silence, greaterThanOrEqualTo(const Duration(seconds: 25)));
        expect(silence, lessThan(KeepalivePinger.lostAfter));
      });
    });

    test('with nothing measured yet waits the longest', () {
      run(() {
        resumable = true;
        pinger.start(foreground: true);

        final silence = silenceUntilLost();

        expect(silence, greaterThanOrEqualTo(const Duration(seconds: 30)));
        expect(silence, lessThan(KeepalivePinger.lostAfter));
      });
    });
  });

  test('a session that dies with its transport keeps the full limit', () {
    run(() {
      pinger.start(foreground: true);
      answerPings(5, const Duration(milliseconds: 40));

      expect(
        silenceUntilLost(),
        greaterThanOrEqualTo(KeepalivePinger.lostAfter),
      );
    });
  });

  group('probe', () {
    test('gives up on a link that does not answer in time', () {
      run(() {
        pinger.start(foreground: true);
        pinger.probe();
        async.flushMicrotasks();

        expect(pings, hasLength(1), reason: 'asks now, not at the next tick');
        async.elapse(KeepalivePinger.probeTimeout);

        expect(lost, 1);
        expect(cause, LinkLoss.probe);
      });
    });

    test('a reply keeps the link', () {
      run(() {
        pinger.start(foreground: true);
        pinger.probe();
        async.elapse(const Duration(milliseconds: 300));
        pings.single.complete();
        async.elapse(KeepalivePinger.probeTimeout);

        expect(lost, 0);
        expect(pinger.isRunning, isTrue);
      });
    });

    test('output from the server counts as an answer', () {
      run(() {
        pinger.start(foreground: true);
        pinger.probe();
        async.elapse(const Duration(seconds: 1));
        quality.heard();
        async.elapse(KeepalivePinger.probeTimeout);

        expect(lost, 0);
      });
    });

    test('waits on a ping already out rather than sending another', () {
      run(() {
        pinger.start(foreground: true);
        async.elapse(KeepalivePinger.foregroundInterval);
        pinger.probe();

        expect(pings, hasLength(1));
        async.elapse(KeepalivePinger.probeTimeout);
        expect(lost, 1);
      });
    });

    test('a closed client is lost at once', () {
      run(() {
        pinger.start(foreground: true);
        alive = false;
        pinger.probe();

        expect(lost, 1);
      });
    });

    test('does nothing on a stopped pinger', () {
      run(() {
        pinger.probe();
        async.elapse(KeepalivePinger.probeTimeout * 2);

        expect(pings, isEmpty);
        expect(lost, 0);
      });
    });

    test('a stop cancels a probe in flight', () {
      run(() {
        pinger.start(foreground: true);
        pinger.probe();
        pinger.stop();
        async.elapse(KeepalivePinger.probeTimeout * 2);

        expect(lost, 0);
      });
    });
  });

  group('pingNow', () {
    test('measures at once instead of at the next tick', () {
      run(() {
        pinger.start(foreground: true);
        pinger.pingNow();
        async.elapse(const Duration(milliseconds: 60));
        pings.single.complete();
        async.flushMicrotasks();

        expect(quality.samples, [60]);
      });
    });

    test('does not add a second ping to one already out', () {
      run(() {
        pinger.start(foreground: true);
        async.elapse(KeepalivePinger.foregroundInterval);
        pinger.pingNow();

        expect(pings, hasLength(1));
      });
    });

    test('does nothing on a stopped pinger', () {
      run(() {
        pinger.pingNow();

        expect(pings, isEmpty);
      });
    });
  });

  group('quick probe', () {
    Duration timeToLose() {
      final start = async.elapsed;
      while (lost == 0 && async.elapsed - start < const Duration(seconds: 10)) {
        async.elapse(const Duration(milliseconds: 100));
      }
      return async.elapsed - start;
    }

    test('on a quick link gives up in well under the full timeout', () {
      run(() {
        pinger.start(foreground: true);
        answerPings(5, const Duration(milliseconds: 40));
        pinger.probe(quick: true);

        final waited = timeToLose();
        expect(waited, KeepalivePinger.quickProbeFloor);
        expect(cause, LinkLoss.probe);
      });
    });

    test('waits longer on a slow link', () {
      run(() {
        pinger.start(foreground: true);
        answerPings(5, const Duration(milliseconds: 400));
        pinger.probe(quick: true);

        expect(timeToLose(), const Duration(seconds: 4));
      });
    });

    test('never waits longer than a full probe', () {
      run(() {
        pinger.start(foreground: true);
        answerPings(5, const Duration(milliseconds: 1500));
        pinger.probe(quick: true);

        expect(timeToLose(), KeepalivePinger.probeTimeout);
      });
    });

    test('with nothing measured waits the full probe', () {
      run(() {
        pinger.start(foreground: true);
        pinger.probe(quick: true);

        expect(timeToLose(), KeepalivePinger.probeTimeout);
      });
    });
  });
}

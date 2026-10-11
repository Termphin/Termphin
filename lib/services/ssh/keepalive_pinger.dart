import 'dart:async';

import 'connection_quality.dart';

/// How a link was found dead.
enum LinkLoss {
  /// The client had already closed.
  closed,

  /// The server was silent past [KeepalivePinger.silenceLimit].
  silent,

  /// A [KeepalivePinger.probe] went unanswered.
  probe,
}

/// The keepalive loop: pings the server on a timer, times each round trip into
/// [quality], and calls [onLost] once the server has been silent too long.
///
/// Never has two of its own pings out at once, so a round trip is always timed
/// from the send its reply answers; a stuck ping stays one stuck ping rather
/// than a pile-up behind it.
class KeepalivePinger {
  KeepalivePinger({
    required this.ping,
    required this.isAlive,
    required this.quality,
    required this.onLost,
    bool Function()? resumable,
    int Function()? clock,
  }) : _resumable = resumable ?? _never,
       _clock = clock ?? _defaultClock;

  static bool _never() => false;

  static final _stopwatch = Stopwatch()..start();

  static int _defaultClock() => _stopwatch.elapsedMilliseconds;

  /// Often enough that a stall shows within seconds while someone is looking.
  static const foregroundInterval = Duration(seconds: 5);

  /// The old rate, for a session nobody is watching.
  static const backgroundInterval = Duration(seconds: 15);

  /// No reply for this long and the connection is given up on - when giving
  /// up kills the shell with it, so a stall that would have cleared is worth
  /// sitting out.
  static const lostAfter = Duration(seconds: 45);

  /// The limit when the server keeps the shell across a reconnect, so a wrong
  /// call costs a replay rather than the session: [resumableRttFactor] round
  /// trips, kept between these two.
  static const resumableLostFloor = Duration(seconds: 15);
  static const resumableLostCap = Duration(seconds: 30);
  static const resumableRttFactor = 30;

  /// How long a [probe] waits for any sign of the server.
  static const probeTimeout = Duration(seconds: 5);

  /// A quick probe waits [quickProbeRttFactor] round trips, kept between
  /// [quickProbeFloor] and [probeTimeout].
  static const quickProbeFloor = Duration(milliseconds: 1500);
  static const quickProbeRttFactor = 10;

  final Future<void> Function() ping;

  final bool Function() isAlive;

  final ConnectionQuality quality;

  final void Function(LinkLoss cause) onLost;

  /// Whether the shell survives this transport being dropped.
  final bool Function() _resumable;

  final int Function() _clock;

  Timer? _timer;

  Timer? _probeTimer;

  var _interval = foregroundInterval;

  int? _sentAt;

  var _lastReply = 0;

  /// Bumped on every start and stop, so a reply to a ping from an earlier run
  /// is not taken for one of this run's.
  var _generation = 0;

  bool get isRunning => _timer != null;

  /// How long the server may stay silent before the link is given up.
  Duration get silenceLimit {
    if (!_resumable()) return lostAfter;
    final rtt = quality.recentLatency;
    if (rtt == null) return resumableLostCap;
    final scaled = Duration(milliseconds: rtt * resumableRttFactor);
    if (scaled < resumableLostFloor) return resumableLostFloor;
    if (scaled > resumableLostCap) return resumableLostCap;
    return scaled;
  }

  void start({required bool foreground}) {
    stop();
    _interval = foreground ? foregroundInterval : backgroundInterval;
    _lastReply = _clock();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
    _sentAt = null;
    _generation++;
  }

  void setForeground(bool foreground) {
    final interval = foreground ? foregroundInterval : backgroundInterval;
    if (interval == _interval || _timer == null) return;
    _interval = interval;
    _timer!.cancel();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  /// Asks now instead of at the next tick, and gives the link up unless
  /// something arrives within [probeTimeout]. For the moments a link most
  /// often dies unseen: a network handover, a process thawed from the
  /// background.
  ///
  /// [quick] scales the wait to the link's round trip instead. Right for a
  /// handover, where the new interface is already up and a live link answers
  /// in one; not for a thaw, where the radio may still be waking.
  void probe({bool quick = false}) {
    if (_timer == null || _probeTimer != null) return;
    if (!isAlive()) {
      _lose(LinkLoss.closed);
      return;
    }
    final timeout = quick ? _quickProbeTimeout : probeTimeout;
    _probeTimer = Timer(timeout, () {
      _probeTimer = null;
      if (quality.silence >= timeout) _lose(LinkLoss.probe);
    });
    if (_sentAt == null) _send();
  }

  Duration get _quickProbeTimeout {
    final rtt = quality.recentLatency;
    if (rtt == null) return probeTimeout;
    final scaled = Duration(milliseconds: rtt * quickProbeRttFactor);
    if (scaled < quickProbeFloor) return quickProbeFloor;
    if (scaled > probeTimeout) return probeTimeout;
    return scaled;
  }

  /// Takes a measurement now rather than at the next tick, so a fresh
  /// transport has a round trip to judge [silenceLimit] by from the start.
  void pingNow() {
    if (_timer == null || _sentAt != null || !isAlive()) return;
    _send();
  }

  void _tick() {
    if (!isAlive()) {
      _lose(LinkLoss.closed);
      return;
    }

    if (_sentAt != null) {
      quality.evaluate();
      if (_clock() - _lastReply >= silenceLimit.inMilliseconds) {
        _lose(LinkLoss.silent);
      }
      return;
    }

    _send();
  }

  void _send() {
    final now = _clock();
    _sentAt = now;
    quality.pingSent();
    final generation = _generation;
    ping().then(
      (_) {
        if (generation != _generation) return;
        final sentAt = _sentAt;
        _sentAt = null;
        _lastReply = _clock();
        if (sentAt != null) {
          quality.pingAnswered(Duration(milliseconds: _lastReply - sentAt));
        }
      },
      onError: (Object _) {
        if (generation != _generation) return;
        _sentAt = null;
        if (_clock() - _lastReply >= silenceLimit.inMilliseconds) {
          _lose(LinkLoss.silent);
        }
      },
    );
  }

  void _lose(LinkLoss cause) {
    stop();
    onLost(cause);
  }
}

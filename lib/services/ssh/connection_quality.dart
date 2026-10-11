import 'package:flutter/foundation.dart';

enum ConnectionHealth { good, slow, unresponsive }

/// Round trips of the SSH keepalive ping, and how long the server has been
/// quiet. Says when the link is bad enough to be worth telling the user about;
/// a good link says nothing.
class ConnectionQuality extends ChangeNotifier {
  ConnectionQuality({int Function()? clock}) : _clock = clock ?? _defaultClock {
    _lastHeard = _clock();
  }

  static final _stopwatch = Stopwatch()..start();

  static int _defaultClock() => _stopwatch.elapsedMilliseconds;

  final int Function() _clock;

  /// Latency above which the link is called slow, and at or below which it is
  /// fine again. The gap keeps a link hovering around one number from
  /// flickering.
  static const slowAboveMs = 300;
  static const fineAtOrBelowMs = 200;

  /// An unanswered ping this old, with nothing else heard meanwhile, is a
  /// server that stopped answering.
  static const unresponsiveAfterMs = 5000;

  /// Round trips [recentLatency] takes its median over.
  static const maxSamples = 5;

  final _samples = <int>[];

  /// The latest round trips in milliseconds, oldest first.
  List<int> get samples => List.unmodifiable(_samples);

  /// Median of the last [maxSamples] round trips - what "slow" is judged on.
  /// One reply that sat out a stall would hold an average up long after the
  /// link recovered; a median lets it go after three.
  ///
  /// A reply slow enough to have been a stall is left out: that stretch was
  /// already shown as unresponsive, and naming it again as latency once the
  /// link is back would be a second alarm for one event.
  int? get recentLatency {
    final recent = _samples.where((ms) => ms < unresponsiveAfterMs).toList()
      ..sort();
    if (recent.isEmpty) return null;
    return recent[recent.length ~/ 2];
  }

  late int _lastHeard;

  int? _pingSentAt;

  var _health = ConnectionHealth.good;

  ConnectionHealth get health => _health;

  /// How long since anything came back from the server.
  Duration get silence => Duration(milliseconds: _clock() - _lastHeard);

  void pingSent() {
    _pingSentAt ??= _clock();
  }

  void pingAnswered(Duration roundTrip) {
    final ms = roundTrip.inMilliseconds;
    _pingSentAt = null;
    _samples.add(ms);
    if (_samples.length > maxSamples) _samples.removeAt(0);
    heard();
  }

  /// Anything at all arrived from the server.
  void heard() {
    _lastHeard = _clock();
    evaluate();
  }

  /// Re-reads the clock. Silence only shows up by time passing, so whoever
  /// displays [health] calls this on a timer.
  ///
  /// Listeners are notified even when the verdict does not change, while
  /// unresponsive: the silence counter it is judged on moves on its own.
  void evaluate() {
    final now = _clock();
    final sentAt = _pingSentAt;
    final waiting = sentAt != null && now - sentAt >= unresponsiveAfterMs;
    final quiet = now - _lastHeard >= unresponsiveAfterMs;

    ConnectionHealth next;
    if (waiting && quiet) {
      next = ConnectionHealth.unresponsive;
    } else {
      final recent = recentLatency;
      final wasSlow = _health != ConnectionHealth.good;
      if (recent == null) {
        next = ConnectionHealth.good;
      } else if (recent > slowAboveMs ||
          (wasSlow && recent > fineAtOrBelowMs)) {
        next = ConnectionHealth.slow;
      } else {
        next = ConnectionHealth.good;
      }
    }

    if (next != _health) {
      _health = next;
      notifyListeners();
    } else if (next == ConnectionHealth.unresponsive) {
      notifyListeners();
    }
  }

  /// Starts over for a new transport: nothing measured on the old one says
  /// anything about this one.
  void reset() {
    _samples.clear();
    _pingSentAt = null;
    _lastHeard = _clock();
    if (_health != ConnectionHealth.good) {
      _health = ConnectionHealth.good;
      notifyListeners();
    }
  }
}

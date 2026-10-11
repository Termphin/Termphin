import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device has a network interface up, plus signals for the moment
/// one comes back and for a switch between two live ones.
///
/// This is interface state, not reachability: a captive portal or a dead uplink
/// still reads as online. That resolution is the right one for what this drives
/// - a reconnect that fires a moment too eagerly costs one failed handshake,
/// while one that never fires leaves a dead terminal on screen until the user
/// notices and taps.
class NetworkMonitor {
  NetworkMonitor({
    Stream<List<ConnectivityResult>>? changes,
    Future<List<ConnectivityResult>> Function()? probe,
    bool initiallyOnline = true,
  }) : _changes = changes ?? _platformChanges(),
       _probe = probe ?? _platformProbe,
       _online = initiallyOnline;

  static final NetworkMonitor instance = NetworkMonitor();

  static Stream<List<ConnectivityResult>> _platformChanges() =>
      Connectivity().onConnectivityChanged;

  static Future<List<ConnectivityResult>> _platformProbe() =>
      Connectivity().checkConnectivity();

  final Stream<List<ConnectivityResult>> _changes;
  final Future<List<ConnectivityResult>> Function() _probe;
  final StreamController<void> _regained = StreamController<void>.broadcast();
  final StreamController<void> _handover = StreamController<void>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online;

  /// The live interfaces last reported, or null before the first reading.
  Set<ConnectivityResult>? _interfaces;

  /// Optimistic until proven otherwise: a monitor that never started must not
  /// be what stops a reconnect from being attempted.
  bool get isOnline => _online;

  /// Fires when a device that had no network gets one back. Never fires for a
  /// change between two live interfaces - that is [onHandover].
  Stream<void> get onRegained => _regained.stream;

  /// Fires when the set of live interfaces changes while online - WiFi to
  /// mobile, or one of two dropping out. A socket bound to the address that
  /// left does not error, it goes silent, so the keepalive would only notice
  /// after its whole silence limit.
  Stream<void> get onHandover => _handover.stream;

  Future<void> init() async {
    _subscription ??= _changes.listen(_onChanged);
    await refresh();
  }

  /// Re-reads the platform's interface state and reports a comeback if one was
  /// missed.
  ///
  /// [onRegained] fires on a transition, so the cached reading has to be
  /// right. Android freezes a backgrounded process and `connectivity_plus`
  /// replays nothing on resume, which leaves a device that went offline and
  /// came back looking permanently offline - and every reconnect parked
  /// against a comeback event that already happened.
  ///
  /// A platform that cannot answer leaves the last known state in place.
  Future<void> refresh() async {
    if (_regained.isClosed) return;
    try {
      _onChanged(await _probe());
    } catch (_) {}
  }

  void _onChanged(List<ConnectivityResult> results) {
    final interfaces = results
        .where((result) => result != ConnectivityResult.none)
        .toSet();
    final online = interfaces.isNotEmpty;
    final previous = _interfaces;
    final regained = online && !_online;
    final handover =
        online &&
        previous != null &&
        previous.isNotEmpty &&
        !setEquals(previous, interfaces);
    _online = online;
    _interfaces = interfaces;
    if (_regained.isClosed) return;
    if (regained) _regained.add(null);
    if (handover) _handover.add(null);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _regained.close();
    await _handover.close();
  }
}

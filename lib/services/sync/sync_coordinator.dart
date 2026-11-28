import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../analytics/analytics_service.dart';
import 'sync_engine.dart';
import 'sync_service.dart';

/// What automatic sync is doing, for the account screen.
enum SyncActivity {
  idle,
  syncing,
  failed,

  /// Stopped because the account no longer has Pro; picks up when it does.
  paused,
}

/// Keeps a device in sync without anyone pressing a button.
///
/// Once the device holds the key, a sync runs:
/// - when the app starts, and when it comes back after [resumeGap];
/// - [localDelay] after the last edit on this device, so typing a profile
///   does not sync each keystroke;
/// - [remoteDelay] after another device writes, while this one is open;
/// - when the network comes back after a run that failed for want of it.
///
/// Runs never overlap: a reason that arrives during one queues exactly one
/// more after it. What a run pulls in or deletes here is handed to
/// [reload], and the edits that reload causes are not mistaken for the
/// user's own. An account that loses Pro, or a device that forgets its
/// key, stops the whole thing quietly into [SyncActivity.paused]; sync
/// turned off or rekeyed on another device stops it and says so in
/// [ended]; a network error just
/// waits for the next reason.
class SyncCoordinator {
  SyncCoordinator({
    required SyncService service,
    required Future<void> Function() reload,
    this.localDelay = const Duration(seconds: 4),
    this.remoteDelay = const Duration(seconds: 2),
    this.resumeGap = const Duration(minutes: 1),
    this.startRetry = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _service = service,
       _reload = reload,
       _now = now ?? DateTime.now;

  final SyncService _service;
  final Future<void> Function() _reload;
  final DateTime Function() _now;

  final Duration localDelay;
  final Duration remoteDelay;
  final Duration resumeGap;

  /// How long [start] waits before asking again when the account could not
  /// be read, doubled after each failure up to 32 times as long. Signing in
  /// on a new device is when that happens most - the network or the token
  /// not ready yet - and nothing else would start sync until a relaunch.
  final Duration startRetry;

  final activity = ValueNotifier<SyncActivity>(SyncActivity.idle);

  /// Why sync last stopped for good on this device - turned off, or given a
  /// new passphrase, from another one - for the card to say so once.
  final ended = ValueNotifier<SyncFailure?>(null);

  /// Whether automatic sync runs on this device, for notes that ask to turn it on.
  final running = ValueNotifier<bool>(false);

  /// When the device last synced, from the service.
  ValueListenable<DateTime?> get lastSynced => _service.lastSynced;

  bool _active = false;
  bool _reloading = false;
  bool _again = false;
  Future<SyncReport?>? _running;
  Timer? _timer;
  Timer? _startTimer;
  int _startFailures = 0;
  StreamSubscription<void>? _remote;
  String? _watching;

  /// Whether automatic sync is on for this device right now.
  bool get active => _active;

  /// Turns automatic sync on if this device can sync, and syncs. Called at
  /// launch, on sign-in, and after a passphrase is set or entered. An
  /// account that cannot be read is asked again after [startRetry]; one
  /// without Pro pauses until [proConfirmed].
  Future<void> start() async {
    ended.value = null;
    _startTimer?.cancel();
    _startTimer = null;
    SyncState state;
    try {
      state = await _service.state();
    } on SyncException catch (error) {
      if (error.failure == SyncFailure.notPro) {
        stop();
        activity.value = SyncActivity.paused;
      } else {
        _retryStart();
      }
      return;
    } catch (_) {
      _retryStart();
      return;
    }
    _startFailures = 0;
    if (state != SyncState.ready) {
      stop();
      return;
    }
    _active = true;
    running.value = true;
    _watchRemote();
    await syncNow();
  }

  /// Turns automatic sync off: on sign-out, or when the device forgets its
  /// key.
  void stop() {
    _active = false;
    running.value = false;
    _timer?.cancel();
    _timer = null;
    _startTimer?.cancel();
    _startTimer = null;
    _startFailures = 0;
    unawaited(_remote?.cancel());
    _remote = null;
    _watching = null;
    activity.value = SyncActivity.idle;
  }

  /// Something on this device changed: machines, keys, snippets or groups.
  void localChanged() {
    if (!_active || _reloading) return;
    _schedule(localDelay);
  }

  /// The device is online again. A run that failed meanwhile is tried
  /// again at once, rather than waiting for the next edit to send it.
  void networkRegained() {
    if (_startNowIfRetrying()) return;
    if (!_active || activity.value != SyncActivity.failed) return;
    _schedule(Duration.zero);
  }

  /// The account was confirmed to have Pro. A device paused for the want of
  /// it - often only because its first sync after sign-in ran before the
  /// purchase reached the account - starts again.
  void proConfirmed() {
    if (_active || activity.value != SyncActivity.paused) return;
    unawaited(start());
  }

  /// The app came back to the foreground.
  void resumed() {
    if (_startNowIfRetrying()) return;
    if (!_active) return;
    final last = _service.lastSynced.value;
    if (last != null && _now().difference(last) < resumeGap) return;
    _schedule(Duration.zero);
  }

  /// Syncs now, or right after the run in progress. Null when nothing ran.
  Future<SyncReport?> syncNow() {
    _timer?.cancel();
    _timer = null;
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _run();
    _running = run;
    return run;
  }

  /// Tries a [start] that could not read the account at once, rather than
  /// after its wait - for the network coming back or the app returning.
  /// False when none is waiting.
  bool _startNowIfRetrying() {
    if (_active || _startTimer == null) return false;
    unawaited(start());
    return true;
  }

  void _retryStart() {
    final delay = startRetry * (1 << min(_startFailures, 5));
    _startFailures++;
    _startTimer = Timer(delay, () => unawaited(start()));
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(syncNow()));
  }

  void _watchRemote() {
    final uid = _service.uid;
    if (uid == null || _watching == uid) return;
    unawaited(_remote?.cancel());
    _watching = uid;
    _remote = _service.watchRemote(uid).listen((_) {
      if (_active) _schedule(remoteDelay);
    }, onError: (Object _) {});
  }

  Future<SyncReport?> _run() async {
    SyncReport? report;
    try {
      do {
        _again = false;
        activity.value = SyncActivity.syncing;
        report = await _service.syncNow();
        if (report.pulled > 0 || report.deletedHere > 0) {
          _reloading = true;
          try {
            await _reload();
          } finally {
            _reloading = false;
          }
        }
      } while (_again && _active);
      activity.value = SyncActivity.idle;
    } on SyncException catch (error) {
      if (error.failure != SyncFailure.network) {
        _noteFailed(analyticsName(error.failure));
      }
      switch (error.failure) {
        case SyncFailure.notPro:
          stop();
          activity.value = SyncActivity.paused;
        case SyncFailure.turnedOff || SyncFailure.passphraseChanged:
          stop();
          ended.value = error.failure;
        default:
          activity.value = SyncActivity.failed;
      }
    } catch (_) {
      _noteFailed('unknown');
      activity.value = SyncActivity.failed;
    } finally {
      _running = null;
    }
    return report;
  }

  /// Records a sync that failed for a reason worth knowing about. A missing
  /// network is not one: it would be sent on every try made offline.
  void _noteFailed(String reason) => unawaited(
    AnalyticsService.instance.capture(
      AnalyticsEvent.syncFailed,
      properties: {AnalyticsProperty.reason: reason},
    ),
  );

  void dispose() {
    stop();
    activity.dispose();
    ended.dispose();
  }
}

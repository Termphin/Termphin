import 'dart:async';

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
/// - [remoteDelay] after another device writes, while this one is open.
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

  final activity = ValueNotifier<SyncActivity>(SyncActivity.idle);

  /// Why sync last stopped for good on this device - turned off, or given a
  /// new passphrase, from another one - for the card to say so once.
  final ended = ValueNotifier<SyncFailure?>(null);

  /// When the device last synced, from the service.
  ValueListenable<DateTime?> get lastSynced => _service.lastSynced;

  bool _active = false;
  bool _reloading = false;
  bool _again = false;
  Future<SyncReport?>? _running;
  Timer? _timer;
  StreamSubscription<void>? _remote;
  String? _watching;

  /// Whether automatic sync is on for this device right now.
  bool get active => _active;

  /// Turns automatic sync on if this device can sync, and syncs. Called at
  /// launch, on sign-in, and after a passphrase is set or entered.
  Future<void> start() async {
    ended.value = null;
    SyncState state;
    try {
      state = await _service.state();
    } catch (_) {
      return;
    }
    if (state != SyncState.ready) {
      stop();
      return;
    }
    _active = true;
    _watchRemote();
    await syncNow();
  }

  /// Turns automatic sync off: on sign-out, or when the device forgets its
  /// key.
  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
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

  /// The app came back to the foreground.
  void resumed() {
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

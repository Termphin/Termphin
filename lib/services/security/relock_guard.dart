import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../settings/lock_settings.dart';
import 'lock_service.dart';

/// Puts the lock screen back after the app has been out of sight for longer
/// than [lockTimeoutSetting].
///
/// The process outlives the screen - the foreground service keeps it running
/// while sessions are open - so a lock checked only at startup is asked for
/// once and never again: whoever picked the phone up next got the terminal
/// back from recents, a notification or a home screen shortcut.
///
/// The decision is made the moment the app is shown, from a monotonic clock
/// started when it was hidden, and [holding] answers it before then too: a
/// shortcut's intent reaches the app ahead of the resume that follows it, and
/// it must already see the lock that resume is about to put up.
class RelockGuard extends ChangeNotifier {
  RelockGuard._();

  static final RelockGuard instance = RelockGuard._();

  final _clock = Stopwatch()..start();
  Duration _offset = Duration.zero;

  bool _armed = false;
  bool _lockEnabled = false;
  bool _locked = false;
  Duration? _hiddenAt;
  final _pending = <VoidCallback>[];

  /// Whether the lock screen is over the app.
  bool get locked => _locked;

  /// Whether anything arriving from outside - a shortcut, a link - has to
  /// wait: the app is locked, or will be as soon as it is shown.
  bool get holding => _locked || _due;

  Duration get _now => _clock.elapsed + _offset;

  bool get _due {
    final hiddenAt = _hiddenAt;
    if (!_armed || !_lockEnabled || hiddenAt == null) return false;
    return _now - hiddenAt >= lockTimeoutSetting.value.after;
  }

  /// The app is past the startup lock, or never had one. Before this the
  /// startup gate is the lock, and a second one over it would ask twice.
  Future<void> arm() async {
    _armed = true;
    _lockEnabled = await LockService.instance.isLockEnabled;
  }

  /// Starts the clock the next [appShown] (or [_due]) measures against.
  ///
  /// Whether the lock is enabled is read again on the way out, since it may
  /// have been switched on or off since [arm]. An immediate timeout locks
  /// right away rather than waiting for [appShown], so not even a frame of
  /// the terminal shows on the way back.
  void appHidden() {
    if (!_armed || _locked) return;
    _hiddenAt = _now;
    LockService.instance.isLockEnabled.then((enabled) {
      _lockEnabled = enabled;
      if (_due && lockTimeoutSetting.value == LockTimeout.immediately) {
        _lock();
      }
    });
  }

  void appShown() {
    if (_due) _lock();
    _hiddenAt = null;
  }

  /// Runs [action] now, or once the PIN has been entered.
  void whenUnlocked(VoidCallback action) {
    if (holding) {
      _pending.add(action);
    } else {
      action();
    }
  }

  void unlocked() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
    final pending = List.of(_pending);
    _pending.clear();
    for (final action in pending) {
      action();
    }
  }

  void _lock() {
    _hiddenAt = null;
    if (_locked) return;
    _locked = true;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    notifyListeners();
  }

  /// Moves the guard's clock on, for tests that cannot wait half a minute.
  @visibleForTesting
  void debugAdvance(Duration by) => _offset += by;

  @visibleForTesting
  void debugReset() {
    _armed = false;
    _lockEnabled = false;
    _locked = false;
    _hiddenAt = null;
    _offset = Duration.zero;
    _pending.clear();
  }
}

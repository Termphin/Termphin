import 'setting.dart';

const kLockTimeoutPrefsKey = 'lock_timeout';

/// How long the app may be out of sight before the PIN is asked for again.
///
/// Not "immediately" by default: the system file and folder pickers, a share
/// sheet and the biometric prompt on some phones all take the app off screen
/// for a moment, and asking again after each of them would teach people to
/// turn the lock off.
enum LockTimeout {
  immediately(Duration.zero),
  seconds30(Duration(seconds: 30)),
  minute1(Duration(minutes: 1)),
  minutes5(Duration(minutes: 5));

  const LockTimeout(this.after);

  final Duration after;
}

final Setting<LockTimeout> lockTimeoutSetting = Setting.option(
  kLockTimeoutPrefsKey,
  fallback: LockTimeout.seconds30,
  values: LockTimeout.values,
);

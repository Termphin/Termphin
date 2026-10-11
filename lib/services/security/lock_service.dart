import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/strings.g.dart';

const kLockEnabledPrefsKey = 'lock_enabled';
const kLockPinPrefsKey = 'lock_pin';
const kLockBiometricPrefsKey = 'lock_biometric';
const kLockPinLengthPrefsKey = 'lock_pin_length';
const kLockFailedAttemptsPrefsKey = 'lock_failed_attempts';

/// PINs are 4 to 6 digits. Every PIN set before 6 was allowed has 4.
const kMinPinLength = 4;
const kMaxPinLength = 6;
const kLockLockedUntilPrefsKey = 'lock_locked_until';

/// Wrong PINs allowed before the first pause.
const kLockFreeAttempts = 3;

/// The pause after [failures] wrong PINs in a row: none for the first
/// [kLockFreeAttempts], then 30 seconds, doubling, up to 15 minutes.
Duration lockoutAfter(int failures) {
  if (failures < kLockFreeAttempts) return Duration.zero;
  final seconds = 30 * (1 << (failures - kLockFreeAttempts).clamp(0, 10));
  return Duration(seconds: seconds.clamp(30, 15 * 60));
}

/// What entering a PIN came to.
class PinAttempt {
  const PinAttempt._({
    required this.unlocked,
    required this.lockout,
    required this.triesLeft,
  });

  const PinAttempt.unlocked()
    : this._(unlocked: true, lockout: Duration.zero, triesLeft: 0);

  /// Refused - either wrong, or not even checked because a pause is running.
  final bool unlocked;

  /// How long until the next PIN is looked at; zero when it can be now.
  final Duration lockout;

  /// Wrong PINs left before a pause starts; zero once pauses have begun.
  final int triesLeft;
}

/// Stored as `pbkdf2$<iterations>$<salt>$<hash>`. A 4-digit PIN has a keyspace
/// of 10^4, so this does not protect against anyone holding the file - it
/// stops the PIN being readable from a dump, which matters mostly because
/// people reuse PINs across apps. The app lock is a UI gate, not a
/// cryptographic boundary.
///
/// For the same reason the round count is set by how long an unlock takes,
/// not by an attacker: 100k rounds of pure-Dart PBKDF2 held a correct PIN on
/// screen for seconds on a budget phone, and bought nothing against a keyspace
/// that small. What slows guessing on the device is [LockService.attemptPin]'s
/// lockout. A record with more rounds is rewritten on the next unlock.
const _pbkdf2Prefix = 'pbkdf2';
const _pbkdf2Iterations = 20000;
const _saltBytes = 16;
const _hashBytes = 32;

class LockService {
  LockService._() {
    availableBiometrics = _auth.getAvailableBiometrics;
  }
  static final LockService instance = LockService._();

  final _auth = LocalAuthentication();

  Future<bool> get isLockEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kLockEnabledPrefsKey) ?? false;
  }

  Future<bool> get isBiometricEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kLockBiometricPrefsKey) ?? false;
  }

  /// False on a platform `local_auth` has no implementation for, such as
  /// Linux.
  Future<bool> get isBiometricAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// How many digits the lock screen waits for before checking. Kept beside
  /// the hash so the screen can draw that many dots and check on the last
  /// one; it tells anyone reading the file little they could not guess.
  Future<int> get pinLength async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(kLockPinLengthPrefsKey) ?? kMinPinLength;
    return stored.clamp(kMinPinLength, kMaxPinLength);
  }

  /// The biometrics the device has enrolled, read through a seam so a test
  /// can stand in for the platform.
  @visibleForTesting
  late Future<List<BiometricType>> Function() availableBiometrics;

  /// Whether the biometric unlock is a face scan - Face ID on an iPhone -
  /// rather than a fingerprint, so the lock screen can draw the right key.
  Future<bool> get unlocksWithFace async {
    try {
      final enrolled = await availableBiometrics();
      return enrolled.contains(BiometricType.face) &&
          !enrolled.contains(BiometricType.fingerprint);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    if (pin.length < kMinPinLength ||
        pin.length > kMaxPinLength ||
        !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError.value(pin.length, 'pin', 'must be 4 to 6 digits');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLockPinPrefsKey, await _hash(pin));
    await prefs.setInt(kLockPinLengthPrefsKey, pin.length);
    await prefs.setBool(kLockEnabledPrefsKey, true);
    await resetAttempts();
  }

  Future<void> disableLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kLockEnabledPrefsKey, false);
    await prefs.remove(kLockPinPrefsKey);
    await prefs.remove(kLockPinLengthPrefsKey);
    await prefs.setBool(kLockBiometricPrefsKey, false);
    await resetAttempts();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kLockBiometricPrefsKey, enabled);
  }

  /// [localizedReason] is what the system's own biometric sheet shows, so it
  /// is a translated string rather than a literal.
  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: t.lock.authenticateReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  /// Where "now" comes from, so a test can walk through a lockout.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Time left on a pause from earlier wrong PINs. Kept in preferences, so
  /// closing the app does not reset it.
  Future<Duration> lockoutRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(kLockLockedUntilPrefsKey);
    if (until == null) return Duration.zero;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks [input] unless a pause is running, and counts the result.
  Future<PinAttempt> attemptPin(String input) async {
    final waiting = await lockoutRemaining();
    if (waiting > Duration.zero) {
      return PinAttempt._(unlocked: false, lockout: waiting, triesLeft: 0);
    }
    if (await verifyPin(input)) {
      await resetAttempts();
      return const PinAttempt.unlocked();
    }
    final prefs = await SharedPreferences.getInstance();
    final failures = (prefs.getInt(kLockFailedAttemptsPrefsKey) ?? 0) + 1;
    await prefs.setInt(kLockFailedAttemptsPrefsKey, failures);
    final lockout = lockoutAfter(failures);
    if (lockout > Duration.zero) {
      await prefs.setInt(
        kLockLockedUntilPrefsKey,
        clock().add(lockout).millisecondsSinceEpoch,
      );
    }
    return PinAttempt._(
      unlocked: false,
      lockout: lockout,
      triesLeft: (kLockFreeAttempts - failures).clamp(0, kLockFreeAttempts),
    );
  }

  /// Any unlock - PIN or biometric - clears the count of wrong PINs.
  Future<void> resetAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kLockFailedAttemptsPrefsKey);
    await prefs.remove(kLockLockedUntilPrefsKey);
  }

  /// A PIN stored before hashing shipped is upgraded in place on the first
  /// successful unlock, so nobody has to re-enter one they already set. One
  /// hashed with more rounds than [_pbkdf2Iterations] is rewritten too, but
  /// after the answer: the unlock does not wait for it.
  Future<bool> verifyPin(String input) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kLockPinPrefsKey);
    if (saved == null) return false;

    final record = _Pbkdf2Record.parse(saved);
    if (record == null) {
      if (!_constantTimeEquals(utf8.encode(input), utf8.encode(saved))) {
        return false;
      }
      await prefs.setString(kLockPinPrefsKey, await _hash(input));
      return true;
    }
    final ok = _constantTimeEquals(
      await _derive(input, record.salt, record.iterations),
      record.hash,
    );
    if (ok && record.iterations != _pbkdf2Iterations) {
      unawaited(_rehash(prefs, input));
    }
    return ok;
  }

  Future<void> _rehash(SharedPreferences prefs, String pin) async =>
      prefs.setString(kLockPinPrefsKey, await _hash(pin));

  Future<String> _hash(String pin) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => random.nextInt(256)),
    );
    final hash = await _derive(pin, salt, _pbkdf2Iterations);
    return '$_pbkdf2Prefix\$$_pbkdf2Iterations'
        '\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  /// Runs off the UI isolate: 100k rounds of PBKDF2 in pure Dart is long
  /// enough to drop frames on the unlock screen.
  Future<Uint8List> _derive(String pin, Uint8List salt, int iterations) =>
      compute(_derivePbkdf2, _Pbkdf2Request(pin, salt, iterations));
}

class _Pbkdf2Request {
  const _Pbkdf2Request(this.pin, this.salt, this.iterations);

  final String pin;
  final Uint8List salt;
  final int iterations;
}

Uint8List _derivePbkdf2(_Pbkdf2Request request) {
  final generator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(request.salt, request.iterations, _hashBytes));
  return generator.process(Uint8List.fromList(utf8.encode(request.pin)));
}

class _Pbkdf2Record {
  const _Pbkdf2Record(this.iterations, this.salt, this.hash);

  final int iterations;
  final Uint8List salt;
  final Uint8List hash;

  static _Pbkdf2Record? parse(String value) {
    final parts = value.split(r'$');
    if (parts.length != 4 || parts.first != _pbkdf2Prefix) return null;
    try {
      return _Pbkdf2Record(
        int.parse(parts[1]),
        base64Decode(parts[2]),
        base64Decode(parts[3]),
      );
    } catch (_) {
      return null;
    }
  }
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

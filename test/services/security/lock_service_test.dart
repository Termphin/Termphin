import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/security/lock_service.dart';

Future<String?> storedPin() async =>
    (await SharedPreferences.getInstance()).getString(kLockPinPrefsKey);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => LockService.instance.clock = DateTime.now);

  test('lock is disabled by default', () async {
    expect(await LockService.instance.isLockEnabled, isFalse);
    expect(await storedPin(), isNull);
    expect(await LockService.instance.isBiometricEnabled, isFalse);
  });

  test('setPin enables the lock and never stores the PIN itself', () async {
    await LockService.instance.setPin('1234');

    expect(await LockService.instance.isLockEnabled, isTrue);
    final stored = await storedPin();
    expect(stored, isNotNull);
    expect(stored, isNot(contains('1234')));
    expect(stored, startsWith(r'pbkdf2$'));
  });

  test('disableLock clears PIN and biometric preference', () async {
    await LockService.instance.setPin('1234');
    await LockService.instance.setBiometricEnabled(true);

    await LockService.instance.disableLock();

    expect(await LockService.instance.isLockEnabled, isFalse);
    expect(await storedPin(), isNull);
    expect(await LockService.instance.isBiometricEnabled, isFalse);
  });

  test('verifyPin accepts the set PIN and rejects others', () async {
    await LockService.instance.setPin('1234');

    expect(await LockService.instance.verifyPin('1234'), isTrue);
    expect(await LockService.instance.verifyPin('0000'), isFalse);
  });

  test('verifyPin is false when no PIN is set', () async {
    expect(await LockService.instance.verifyPin('1234'), isFalse);
  });

  test('the same PIN hashes differently for two users', () async {
    await LockService.instance.setPin('1234');
    final first = await storedPin();
    SharedPreferences.setMockInitialValues({});
    await LockService.instance.setPin('1234');

    expect(await storedPin(), isNot(first));
  });

  test('a PIN stored before hashing still unlocks, and is upgraded', () async {
    SharedPreferences.setMockInitialValues({
      kLockEnabledPrefsKey: true,
      kLockPinPrefsKey: '1234',
    });

    expect(await LockService.instance.verifyPin('0000'), isFalse);
    expect(await storedPin(), '1234');

    expect(await LockService.instance.verifyPin('1234'), isTrue);
    expect(await storedPin(), startsWith(r'pbkdf2$'));
    expect(await LockService.instance.verifyPin('1234'), isTrue);
  });

  group('PIN length', () {
    test('4 to 6 digits are accepted and their length kept', () async {
      for (final pin in ['1234', '12345', '123456']) {
        await LockService.instance.setPin(pin);
        expect(await LockService.instance.pinLength, pin.length);
        expect(await LockService.instance.verifyPin(pin), isTrue);
      }
    });

    test('anything else is refused', () async {
      for (final pin in ['123', '1234567', '12a4']) {
        expect(
          () => LockService.instance.setPin(pin),
          throwsArgumentError,
          reason: pin,
        );
      }
    });

    test('a PIN set before lengths were stored is four digits', () async {
      SharedPreferences.setMockInitialValues({kLockEnabledPrefsKey: true});
      expect(await LockService.instance.pinLength, 4);
    });

    test('turning the lock off forgets the length', () async {
      await LockService.instance.setPin('123456');
      await LockService.instance.disableLock();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kLockPinLengthPrefsKey), isNull);
    });
  });

  group('wrong PINs', () {
    test('three are free, then the pause doubles up to a cap', () {
      expect(lockoutAfter(1), Duration.zero);
      expect(lockoutAfter(2), Duration.zero);
      expect(lockoutAfter(3), const Duration(seconds: 30));
      expect(lockoutAfter(4), const Duration(minutes: 1));
      expect(lockoutAfter(5), const Duration(minutes: 2));
      expect(lockoutAfter(40), const Duration(minutes: 15));
    });

    test('a pause refuses even the right PIN until it runs out', () async {
      var now = DateTime(2026, 9, 26, 12);
      LockService.instance.clock = () => now;
      await LockService.instance.setPin('1234');

      final first = await LockService.instance.attemptPin('0000');
      expect(first.unlocked, isFalse);
      expect(first.triesLeft, 2);
      await LockService.instance.attemptPin('0000');
      final third = await LockService.instance.attemptPin('0000');
      expect(third.lockout, const Duration(seconds: 30));

      final during = await LockService.instance.attemptPin('1234');
      expect(during.unlocked, isFalse);
      expect(during.lockout, const Duration(seconds: 30));

      now = now.add(const Duration(seconds: 31));
      expect((await LockService.instance.attemptPin('1234')).unlocked, isTrue);
      expect((await LockService.instance.attemptPin('0000')).triesLeft, 2);
    });

    test('the pause is stored, so a restart does not reset it', () async {
      final now = DateTime(2026, 9, 26, 12);
      LockService.instance.clock = () => now;
      await LockService.instance.setPin('1234');
      for (var i = 0; i < 3; i++) {
        await LockService.instance.attemptPin('0000');
      }

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kLockLockedUntilPrefsKey), isNotNull);
      expect(
        await LockService.instance.lockoutRemaining(),
        const Duration(seconds: 30),
      );
    });

    test('setting a new PIN clears the count', () async {
      await LockService.instance.setPin('1234');
      for (var i = 0; i < 3; i++) {
        await LockService.instance.attemptPin('0000');
      }
      await LockService.instance.setPin('5678');

      expect(await LockService.instance.lockoutRemaining(), Duration.zero);
    });
  });

  test(
    'a PIN hashed with the old round count is rewritten after an unlock',
    () async {
      final salt = Uint8List(16);
      final hash =
          (PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
                ..init(Pbkdf2Parameters(salt, 100000, 32)))
              .process(Uint8List.fromList(utf8.encode('1234')));
      SharedPreferences.setMockInitialValues({
        kLockEnabledPrefsKey: true,
        kLockPinPrefsKey:
            'pbkdf2\$100000\$${base64Encode(salt)}\$${base64Encode(hash)}',
      });

      expect(await LockService.instance.verifyPin('1234'), isTrue);
      for (
        var i = 0;
        i < 50 && (await storedPin())!.contains(r'$100000$');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(await storedPin(), startsWith(r'pbkdf2$20000$'));
      expect(await LockService.instance.verifyPin('1234'), isTrue);
    },
  );
}

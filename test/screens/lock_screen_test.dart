import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/screens/lock_screen.dart';
import 'package:termphin/services/security/lock_service.dart';

import '../support/test_app.dart';

/// Enters [pin], then hands back real time until [until] holds.
///
/// `verifyPin` derives on another isolate, and the fake clock a widget test
/// runs on never advances for it - `pumpAndSettle` alone returns before the
/// answer is back. The pumps in between stay plain: the "checking" spinner
/// turns for as long as the check runs, so there is nothing for
/// `pumpAndSettle` to settle on.
Future<void> _enterPin(
  WidgetTester tester,
  String pin, {
  required bool Function() until,
}) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (until()) return;
  }
}

bool _incorrectPinShown() =>
    find.textContaining('Incorrect PIN').evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      kLockEnabledPrefsKey: true,
      kLockBiometricPrefsKey: false,
    });
    await LockService.instance.setPin('1234');
  });

  testWidgets('unlocks after entering the saved PIN', (tester) async {
    var unlockCount = 0;
    await pumpTestApp(tester, LockScreen(onUnlocked: () => unlockCount++));
    await tester.pumpAndSettle();

    await _enterPin(tester, '1234', until: () => unlockCount == 1);

    expect(unlockCount, 1);
    expect(_incorrectPinShown(), isFalse);
  });

  testWidgets('clears an incorrect PIN and accepts a subsequent attempt', (
    tester,
  ) async {
    var unlockCount = 0;
    await pumpTestApp(tester, LockScreen(onUnlocked: () => unlockCount++));
    await tester.pumpAndSettle();

    await _enterPin(tester, '1111', until: _incorrectPinShown);

    expect(unlockCount, 0);
    expect(_incorrectPinShown(), isTrue);

    await _enterPin(tester, '1234', until: () => unlockCount == 1);

    expect(unlockCount, 1);
    expect(_incorrectPinShown(), isFalse);
  });

  testWidgets('says how many tries are left before a pause', (tester) async {
    await pumpTestApp(tester, LockScreen(onUnlocked: () {}));
    await tester.pumpAndSettle();

    await _enterPin(tester, '1111', until: _incorrectPinShown);

    expect(
      find.text('Incorrect PIN. 2 more tries before a short wait.'),
      findsOneWidget,
    );
  });

  testWidgets('three wrong PINs pause the keypad with a countdown', (
    tester,
  ) async {
    var unlockCount = 0;
    await pumpTestApp(tester, LockScreen(onUnlocked: () => unlockCount++));
    await tester.pumpAndSettle();

    bool paused() =>
        find.textContaining('Too many attempts').evaluate().isNotEmpty;
    for (final wrong in ['1111', '2222']) {
      await _enterPin(tester, wrong, until: _incorrectPinShown);
    }
    await _enterPin(tester, '3333', until: paused);
    expect(find.text('Too many attempts. Try again in 0:30.'), findsOneWidget);

    await _enterPin(tester, '1234', until: () => false);
    expect(unlockCount, 0);
    expect(paused(), isTrue);
  });

  testWidgets('a pause survives closing the app', (tester) async {
    for (final wrong in ['1111', '2222', '3333']) {
      await tester.runAsync(() => LockService.instance.attemptPin(wrong));
    }

    await pumpTestApp(tester, LockScreen(onUnlocked: () {}));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.textContaining('Too many attempts'), findsOneWidget);
  });

  testWidgets('a six-digit PIN is checked on the sixth digit, not the fourth', (
    tester,
  ) async {
    await tester.runAsync(() => LockService.instance.setPin('123456'));
    var unlockCount = 0;
    await pumpTestApp(tester, LockScreen(onUnlocked: () => unlockCount++));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    await _enterPin(tester, '1234', until: () => false);
    expect(_incorrectPinShown(), isFalse);
    expect(unlockCount, 0);

    await _enterPin(tester, '56', until: () => unlockCount == 1);
    expect(unlockCount, 1);
  });

  group('biometric key', () {
    final original = LockService.instance.availableBiometrics;
    tearDown(() => LockService.instance.availableBiometrics = original);

    Future<void> showWith(
      WidgetTester tester,
      List<BiometricType> enrolled,
    ) async {
      await LockService.instance.setBiometricEnabled(true);
      LockService.instance.availableBiometrics = () async => enrolled;
      await pumpTestApp(tester, LockScreen(onUnlocked: () {}));
      await tester.pumpAndSettle();
    }

    testWidgets('is a face on a device that unlocks with Face ID', (
      tester,
    ) async {
      await showWith(tester, [BiometricType.face, BiometricType.strong]);

      expect(find.byIcon(PhosphorIconsRegular.scanSmiley), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.fingerprint), findsNothing);
    });

    testWidgets('is a fingerprint on a device with a fingerprint reader', (
      tester,
    ) async {
      await showWith(tester, [BiometricType.fingerprint, BiometricType.strong]);

      expect(find.byIcon(PhosphorIconsRegular.fingerprint), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.scanSmiley), findsNothing);
    });

    testWidgets('stays a fingerprint when the platform cannot say', (
      tester,
    ) async {
      await showWith(tester, []);

      expect(find.byIcon(PhosphorIconsRegular.fingerprint), findsOneWidget);
    });
  });
}

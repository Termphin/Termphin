@Tags(['security'])
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/app.dart';
import 'package:termphin/screens/lock_screen.dart';
import 'package:termphin/services/app/onboarding_service.dart';
import 'package:termphin/services/security/lock_service.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/widgets/profiles/profile_form_dialog.dart';

import '../support/secure_storage_channel.dart';

/// Nothing from outside the app gets past the lock screen. A link, a home
/// screen shortcut or anything else the system hands over waits until the PIN
/// has been entered - acting on it first would open a session, or show a
/// machine's address, to whoever is holding the phone.
const _link = 'ssh://root@canary-host.example:2222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> quickActionCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      kOnboardingCompletedPrefsKey: true,
      kLockEnabledPrefsKey: true,
      kLockBiometricPrefsKey: false,
    });
    SharedPreferences.resetStatic();
    mockSecureStorage();
    await loadAppSettings();
    await LockService.instance.setPin('1234');
    PackageInfo.setMockInitialValues(
      appName: 'Termphin',
      packageName: 'termphin',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    quickActionCalls = [];
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => call.method == 'getInitialLink' ? _link : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/quick_actions'),
      (call) async {
        quickActionCalls.add(call.method);
        return null;
      },
    );
  });

  tearDown(() {
    messenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/quick_actions'),
      null,
    );
  });

  /// Real time for the gate's storage reads, then a frame to show the result.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unlock(WidgetTester tester) async {
    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(LockScreen).evaluate().isEmpty) break;
    }
    await settle(tester);
  }

  /// One test, not two: the shortcut service is a process-wide singleton that
  /// registers once, so a second test would never see it register.
  testWidgets('a link and a shortcut both wait behind the PIN', (tester) async {
    await tester.pumpWidget(const SshClientApp());
    await settle(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(ProfileFormDialog), findsNothing);
    expect(find.textContaining('canary-host'), findsNothing);
    expect(quickActionCalls, isNot(contains('getLaunchAction')));

    await unlock(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(ProfileFormDialog), findsOneWidget);
    expect(quickActionCalls, contains('getLaunchAction'));
  });
}

@Tags(['security'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/app.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/screens/lock_screen.dart';
import 'package:termphin/services/app/onboarding_service.dart';
import 'package:termphin/services/security/lock_service.dart';
import 'package:termphin/services/security/relock_guard.dart';
import 'package:termphin/services/settings/app_settings.dart';

import '../support/fixtures.dart';
import '../support/secure_storage_channel.dart';

/// A home screen shortcut tapped after the app has been away long enough
/// opens nothing until the PIN is in. Its intent reaches the app before the
/// resume that puts the lock back, so it has to see the lock coming.
///
/// A file of its own: the shortcut service is a process-wide singleton that
/// registers once, so it only ever registers in the first test of a file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': SshProfile.encodeList([
        profileFixture(id: 'canary-machine', name: 'Canary'),
      ]),
      kOnboardingCompletedPrefsKey: true,
      kLockEnabledPrefsKey: true,
      kLockBiometricPrefsKey: false,
    });
    SharedPreferences.resetStatic();
    mockSecureStorage();
    await loadAppSettings();
    await LockService.instance.setPin('1234');
    RelockGuard.instance.debugReset();
    PackageInfo.setMockInitialValues(
      appName: 'Termphin',
      packageName: 'termphin',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/quick_actions'),
      (call) async => null,
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
    RelockGuard.instance.debugReset();
  });

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
      await tester.tap(find.text(digit).last);
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

  Future<void> leave(WidgetTester tester) async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
  }

  Future<void> comeBack(WidgetTester tester) async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
  }

  Future<void> openUnlocked(WidgetTester tester) async {
    await tester.pumpWidget(const SshClientApp());
    await settle(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    await unlock(tester);
    expect(find.byType(LockScreen), findsNothing);
  }

  testWidgets('a shortcut after time away waits behind the PIN', (
    tester,
  ) async {
    await openUnlocked(tester);
    final container = ProviderScope.containerOf(navigatorKey.currentContext!);
    final opened = <String?>[];
    final subscription = container.listen(
      terminalOverlayProvider,
      (_, next) => opened.add(next?.$2.id),
    );
    addTearDown(subscription.close);

    await leave(tester);
    RelockGuard.instance.debugAdvance(const Duration(minutes: 2));
    await messenger.handlePlatformMessage(
      'plugins.flutter.io/quick_actions',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('launch', 'canary-machine'),
      ),
      (_) {},
    );
    await settle(tester);
    expect(opened, isEmpty);

    await comeBack(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(opened, isEmpty);

    await unlock(tester);
    expect(opened, ['canary-machine']);

    container.read(terminalOverlayProvider.notifier).hide();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}

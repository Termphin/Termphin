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
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/services/settings/toolbar_share_link.dart';
import 'package:termphin/widgets/terminal/toolbar_import_sheet.dart';

import '../support/secure_storage_channel.dart';

/// A toolbar link that opens the app waits behind the PIN like any other: the
/// sheet it opens shows what the layout's keys type, and adding it changes
/// the toolbar every session draws.
final _link = toolbarShareLink(
  name: 'Canary layout',
  layout: ToolbarLayout(
    order: [
      'esc',
      toolbarCustomActionId(text: 'canary-command'),
    ],
    columns: 5,
    rows: 2,
    pages: 1,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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

  testWidgets('a toolbar link waits behind the PIN', (tester) async {
    await tester.pumpWidget(const SshClientApp());
    await settle(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(ToolbarImportSheet), findsNothing);
    expect(find.textContaining('canary'), findsNothing);

    await unlock(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(ToolbarImportSheet), findsOneWidget);
    expect(find.text('Canary layout'), findsOneWidget);
  });
}

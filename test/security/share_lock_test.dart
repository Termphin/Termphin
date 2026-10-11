@Tags(['security'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/app.dart';
import 'package:termphin/screens/lock_screen.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/screens/share/share_screen.dart';
import 'package:termphin/services/platform/share_intent_service.dart';
import 'package:termphin/services/security/lock_service.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/sftp/upload_plan.dart';

import '../support/secure_storage_channel.dart';

/// A share opens on its own screen, over the app it came from - and still
/// behind the PIN. Before it is entered nothing is read from the share and
/// no machine is listed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      kLockEnabledPrefsKey: true,
      kLockBiometricPrefsKey: false,
    });
    SharedPreferences.resetStatic();
    mockSecureStorage();
    await loadAppSettings();
    await LockService.instance.setPin('1234');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a share waits behind the PIN', (tester) async {
    var taken = 0;
    await tester.pumpWidget(
      SshClientApp(
        home: ShareGate(
          take: () async {
            taken++;
            return SharedContent([
              LocalUpload(
                name: 'canary.txt',
                open: () => const Stream.empty(),
                length: () async => 1,
              ),
            ]);
          },
          finish: () async {},
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(taken, 0);
    expect(find.byType(GlobalSearchScreen), findsNothing);

    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    for (var i = 0; i < 100; i++) {
      await settle(tester);
      if (find.byType(LockScreen).evaluate().isEmpty) break;
    }
    await settle(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(taken, 1);
    expect(find.byType(GlobalSearchScreen), findsOneWidget);
    expect(find.text('canary.txt'), findsOneWidget);
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/widgets/account/sign_in_panel.dart';

import '../../support/fake_account_backend.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  late FakeAccountBackend backend;
  final opened = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAccountBackend();
    AccountService.backendOverride = () => backend;
    AccountService.instance.resetForTest();
    opened.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            opened.add('${(call.arguments as Map)['url']}');
            return true;
          },
        );
  });

  tearDown(() {
    AccountService.backendOverride = null;
    AccountService.instance.resetForTest();
  });

  Future<void> show(WidgetTester tester) => pumpTestApp(
    tester,
    const Scaffold(body: SingleChildScrollView(child: SignInPanel())),
  );

  testWidgets('on a phone, it offers the providers and an email form', (
    tester,
  ) async {
    await show(tester);

    expect(find.text(t.account.continueWithGoogle), findsOneWidget);
    expect(find.byKey(const ValueKey('browserSignIn')), findsNothing);
  });

  testWidgets('on a computer, it signs in through the account page', (
    tester,
  ) async {
    backend.browser = true;
    await show(tester);

    expect(find.text(t.account.continueWithGoogle), findsNothing);
    await tester.tap(find.byKey(const ValueKey('browserSignIn')));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('browser'));
    expect(AccountService.instance.user?.uid, 'desk');
  });
}

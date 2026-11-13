import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/account_screen.dart';
import 'package:termphin/services/account/account_service.dart';

import '../../support/fake_account_backend.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  late FakeAccountBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAccountBackend();
    AccountService.backendOverride = () => backend;
    AccountService.instance.resetForTest();
  });

  tearDown(() {
    AccountService.backendOverride = null;
    AccountService.instance.resetForTest();
  });

  Future<void> open(WidgetTester tester) async {
    await pumpTestApp(tester, const AccountScreen());
    await tester.pumpAndSettle();
  }

  testWidgets('says the account is only for Pro, then offers the ways in', (
    tester,
  ) async {
    await open(tester);

    expect(find.text(t.account.intro), findsWidgets);
    expect(find.text(t.account.continueWithGoogle), findsOneWidget);
    expect(find.text(t.account.continueWithApple), findsNothing);
    expect(find.text(t.account.createAccount), findsOneWidget);
  });

  testWidgets('Apple is offered where the backend can do it', (tester) async {
    backend.apple = true;

    await open(tester);

    expect(find.text(t.account.continueWithApple), findsOneWidget);
  });

  testWidgets('signing in with Google turns the screen into the account', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text(t.account.continueWithGoogle));
    await tester.pumpAndSettle();

    expect(
      find.text(t.account.signedInAs(name: 'me@example.com')),
      findsOneWidget,
    );
    expect(find.text(t.account.signOut), findsOneWidget);
    expect(find.text(t.account.deleteAccount), findsOneWidget);
  });

  testWidgets('a wrong password is explained, not thrown', (tester) async {
    await open(tester);
    backend.failNext = AccountFailure.wrongCredentials;

    await tester.enterText(find.byType(TextField).first, 'me@example.com');
    await tester.enterText(find.byType(TextField).last, 'nope');
    await tester.tap(find.text(t.account.signInWithEmail).last);
    await tester.pumpAndSettle();

    expect(find.text(t.account.failure.wrongCredentials), findsOneWidget);
    expect(find.text(t.account.signOut), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a cancelled sign-in sheet says nothing', (tester) async {
    await open(tester);
    backend.failNext = AccountFailure.cancelled;

    await tester.tap(find.text(t.account.continueWithGoogle));
    await tester.pumpAndSettle();

    expect(find.text(t.account.failure.unknown), findsNothing);
  });

  testWidgets('deleting asks first, and a password account for its password', (
    tester,
  ) async {
    await AccountService.instance.signInWithEmail('me@example.com', 'secret');
    await open(tester);

    await tester.tap(find.text(t.account.deleteAccount));
    await tester.pumpAndSettle();
    expect(find.text(t.account.deleteTitle), findsOneWidget);
    await tester.tap(find.text(t.account.deleteConfirm).last);
    await tester.pumpAndSettle();
    expect(find.text(t.account.passwordToDelete), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text(t.account.deleteConfirm).last);
    await tester.pumpAndSettle();

    expect(backend.calls, contains('delete:secret'));
    expect(find.text(t.account.continueWithGoogle), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

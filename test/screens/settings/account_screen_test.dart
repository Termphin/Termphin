import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/account_screen.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/pro/pro_service.dart';
import 'package:termphin/services/sync/sync_service.dart';

import '../../support/fake_account_backend.dart';
import '../../support/sync_fakes.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  late FakeAccountBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAccountBackend();
    AccountService.backendOverride = () => backend;
    AccountService.instance.resetForTest();
    SyncService.instanceOverride = SyncService(
      cloud: FakeSyncCloud(),
      vault: FakeSyncVault(),
      local: FakeSyncLocal(),
      uid: () => AccountService.instance.user?.uid,
    );
  });

  tearDown(() {
    ProService.renewsOverride = null;
    SyncService.instanceOverride = null;
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

  testWidgets('signing in says it means agreeing to the terms', (tester) async {
    await open(tester);

    expect(find.text(t.account.agreeNotice), findsOneWidget);
    expect(find.text(t.analyticsConsent.termsLink), findsOneWidget);
    expect(find.text(t.analyticsConsent.privacyLink), findsOneWidget);
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

    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text(t.account.signOut), findsOneWidget);
    expect(find.text(t.account.deleteAccount), findsOneWidget);
  });

  testWidgets('signing in with GitHub turns the screen into the account', (
    tester,
  ) async {
    await open(tester);

    await tester.ensureVisible(find.text(t.account.continueWithGitHub));
    await tester.tap(find.text(t.account.continueWithGitHub));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('github'));
    expect(
      find.text(t.account.signedInWith(provider: t.account.providerGitHub)),
      findsOneWidget,
    );
    expect(find.text(t.account.signOut), findsOneWidget);
  });

  testWidgets('opened only to sign in, it closes once someone has', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AccountScreen(closeOnSignIn: true),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.account.continueWithGoogle));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
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

  testWidgets('a new email account is asked to confirm its address until it '
      'has', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'new@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret1');
    await tester.tap(find.text(t.account.createAccount));
    await tester.pumpAndSettle();

    expect(find.text(t.account.verifyTitle), findsOneWidget);
    expect(
      find.text(t.account.verifyBody(email: 'new@example.com')),
      findsOneWidget,
    );

    await tester.tap(find.text(t.account.verifyCheck));
    await tester.pumpAndSettle();
    expect(find.text(t.account.verifyNotYet), findsOneWidget);
    expect(find.text(t.account.verifyTitle), findsOneWidget);

    await tester.tap(find.text(t.account.verifyResend));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('verify'));

    backend.confirmEmail();
    await tester.tap(find.text(t.account.verifyCheck));
    await tester.pumpAndSettle();
    expect(find.text(t.account.verifyTitle), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('Google vouches for its address: nothing to confirm', (
    tester,
  ) async {
    await AccountService.instance.signInWithGoogle();

    await open(tester);

    expect(find.text(t.account.verifyTitle), findsNothing);
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

  testWidgets(
    'a renewing subscription is pointed out before deleting, then deleting goes on',
    (tester) async {
      ProService.renewsOverride = () async => true;
      await AccountService.instance.signInWithEmail('me@example.com', 'secret');
      await open(tester);

      await tester.tap(find.text(t.account.deleteAccount));
      await tester.pumpAndSettle();
      expect(find.text(t.account.deleteRenewsTitle), findsOneWidget);
      expect(find.text(t.account.deleteRenewsMessage), findsOneWidget);
      expect(find.text(t.account.deleteTitle), findsNothing);

      await tester.tap(find.text(t.account.deleteAnyway));
      await tester.pumpAndSettle();
      expect(find.text(t.account.deleteTitle), findsOneWidget);
    },
  );

  testWidgets('going to manage the subscription deletes nothing', (
    tester,
  ) async {
    ProService.renewsOverride = () async => true;
    await AccountService.instance.signInWithEmail('me@example.com', 'secret');
    await open(tester);

    await tester.tap(find.text(t.account.deleteAccount));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.account.pro.manage).last);
    await tester.pumpAndSettle();

    expect(find.text(t.account.deleteTitle), findsNothing);
    expect(backend.calls.where((call) => call.startsWith('delete')), isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('a subscription that does not renew is not brought up', (
    tester,
  ) async {
    ProService.renewsOverride = () async => false;
    await AccountService.instance.signInWithEmail('me@example.com', 'secret');
    await open(tester);

    await tester.tap(find.text(t.account.deleteAccount));
    await tester.pumpAndSettle();

    expect(find.text(t.account.deleteRenewsTitle), findsNothing);
    expect(find.text(t.account.deleteTitle), findsOneWidget);
  });
}

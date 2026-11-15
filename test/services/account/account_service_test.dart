import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/account/firebase_account_backend.dart';

import '../../support/fake_account_backend.dart';

void main() {
  late FakeAccountBackend backend;
  final service = AccountService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAccountBackend();
    AccountService.backendOverride = () => backend;
    service.resetForTest();
  });

  tearDown(() {
    AccountService.backendOverride = null;
    service.resetForTest();
  });

  Future<bool?> remembered() async =>
      (await SharedPreferences.getInstance()).getBool(kAccountSignedInPrefsKey);

  test('signing in publishes the user and remembers there is one', () async {
    final published = <AccountUser?>[];
    service.changes.listen(published.add);

    await service.signInWithGoogle();
    await pumpEventQueue();

    expect(service.user?.email, 'me@example.com');
    expect(published.last?.provider, AccountProvider.google);
    expect(await remembered(), isTrue);
  });

  test(
    'signing out forgets it, so the next launch leaves Firebase alone',
    () async {
      await service.signInWithGoogle();
      await service.signOut();
      await pumpEventQueue();

      expect(service.user, isNull);
      expect(await remembered(), isFalse);
    },
  );

  test('a launch with nobody signed in before starts nothing', () async {
    await service.init();

    expect(backend.calls, isEmpty);
    expect(service.user, isNull);
  });

  test('a launch after a sign-in picks the user back up', () async {
    await backend.signInWithEmail('me@example.com', 'secret');
    SharedPreferences.setMockInitialValues({kAccountSignedInPrefsKey: true});

    await service.init();

    expect(service.user?.email, 'me@example.com');
  });

  test('an email is trimmed, a password is not', () async {
    await service.signInWithEmail('  me@example.com ', ' secret ');

    expect(backend.calls, ['email:me@example.com']);
  });

  test('a failure reaches the caller as what went wrong', () async {
    backend.failNext = AccountFailure.wrongCredentials;

    await expectLater(
      service.signInWithEmail('me@example.com', 'nope'),
      throwsA(
        isA<AccountException>().having(
          (e) => e.failure,
          'failure',
          AccountFailure.wrongCredentials,
        ),
      ),
    );
    expect(service.user, isNull);
  });

  test('a build without accounts says so instead of trying', () async {
    AccountService.backendOverride = null;

    expect(service.available, isFalse);
    await expectLater(
      service.signInWithGoogle(),
      throwsA(
        isA<AccountException>().having(
          (e) => e.failure,
          'failure',
          AccountFailure.unavailable,
        ),
      ),
    );
  });

  test('closing the GitHub page counts as cancelling, which says nothing', () {
    for (final code in ['web-context-canceled', 'web-context-cancelled']) {
      expect(FirebaseAccountBackend.failureOf(code), AccountFailure.cancelled);
    }
  });

  test('Firebase error codes become failures the screen can explain', () {
    expect(
      FirebaseAccountBackend.failureOf('invalid-credential'),
      AccountFailure.wrongCredentials,
    );
    expect(
      FirebaseAccountBackend.failureOf('wrong-password'),
      AccountFailure.wrongCredentials,
    );
    expect(
      FirebaseAccountBackend.failureOf('email-already-in-use'),
      AccountFailure.emailInUse,
    );
    expect(
      FirebaseAccountBackend.failureOf('requires-recent-login'),
      AccountFailure.requiresRecentLogin,
    );
    expect(
      FirebaseAccountBackend.failureOf('network-request-failed'),
      AccountFailure.network,
    );
    expect(
      FirebaseAccountBackend.failureOf('whatever'),
      AccountFailure.unknown,
    );
  });
}

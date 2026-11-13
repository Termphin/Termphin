import 'dart:async';

import 'package:termphin/services/account/account_service.dart';

/// An account backend that signs in whoever asks, unless told to fail.
class FakeAccountBackend implements AccountBackend {
  final _changes = StreamController<AccountUser?>.broadcast();
  final calls = <String>[];
  AccountUser? _user;
  AccountFailure? failNext;
  bool apple = false;

  void _set(AccountUser? user) {
    _user = user;
    _changes.add(user);
  }

  Future<void> _call(String name, void Function() effect) async {
    calls.add(name);
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw AccountException(failure);
    }
    effect();
  }

  @override
  Stream<AccountUser?> userChanges() => _changes.stream;

  @override
  AccountUser? get currentUser => _user;

  @override
  bool get supportsApple => apple;

  @override
  Future<void> signInWithGoogle() => _call(
    'google',
    () => _set(
      const AccountUser(
        uid: 'g1',
        provider: AccountProvider.google,
        email: 'me@example.com',
      ),
    ),
  );

  @override
  Future<void> signInWithApple() => _call(
    'apple',
    () => _set(const AccountUser(uid: 'a1', provider: AccountProvider.apple)),
  );

  @override
  Future<void> signInWithEmail(String email, String password) => _call(
    'email:$email',
    () => _set(
      AccountUser(uid: 'p1', provider: AccountProvider.password, email: email),
    ),
  );

  @override
  Future<void> createWithEmail(String email, String password) => _call(
    'create:$email',
    () => _set(
      AccountUser(uid: 'p2', provider: AccountProvider.password, email: email),
    ),
  );

  @override
  Future<void> sendPasswordReset(String email) => _call('reset:$email', () {});

  @override
  Future<void> signOut() => _call('signOut', () => _set(null));

  @override
  Future<void> deleteAccount({String? password}) =>
      _call('delete:${password ?? ''}', () => _set(null));
}

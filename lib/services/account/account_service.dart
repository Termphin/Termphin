import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/firebase_service.dart';
import 'firebase_account_backend.dart';

/// Remembers that this device has an account signed in, so Firebase is
/// started at launch only for those who have one.
const kAccountSignedInPrefsKey = 'account_signed_in';

/// How someone signed in, as far as the app needs to tell them apart.
enum AccountProvider { google, apple, password }

/// The signed-in user, as the app sees them.
@immutable
class AccountUser {
  const AccountUser({
    required this.uid,
    required this.provider,
    this.email,
    this.displayName,
    this.emailVerified = true,
  });

  final String uid;
  final AccountProvider provider;
  final String? email;
  final String? displayName;

  /// Whether the address has been shown to belong to the user. Google and
  /// Apple vouch for theirs; a password account confirms its own by the
  /// link mailed when it is created, and Pro waits for that.
  final bool emailVerified;

  @override
  bool operator ==(Object other) =>
      other is AccountUser &&
      other.uid == uid &&
      other.provider == provider &&
      other.email == email &&
      other.displayName == displayName &&
      other.emailVerified == emailVerified;

  @override
  int get hashCode =>
      Object.hash(uid, provider, email, displayName, emailVerified);
}

/// Why signing in, signing up or deleting did not happen, in terms the
/// screen can explain. Never carries the backend's own message, which may
/// quote the address typed.
enum AccountFailure {
  cancelled,
  invalidEmail,
  wrongCredentials,
  emailInUse,
  weakPassword,
  requiresRecentLogin,
  network,
  tooManyRequests,
  unavailable,
  unknown,
}

class AccountException implements Exception {
  const AccountException(this.failure);

  final AccountFailure failure;

  @override
  String toString() => 'AccountException(${failure.name})';
}

/// What an account is made of: Firebase Auth in the app, a fake in tests.
abstract interface class AccountBackend {
  Stream<AccountUser?> userChanges();

  AccountUser? get currentUser;

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  bool get supportsApple;

  Future<void> signInWithEmail(String email, String password);

  Future<void> createWithEmail(String email, String password);

  Future<void> sendPasswordReset(String email);

  /// Mails the signed-in user a link that confirms their address.
  Future<void> sendEmailVerification();

  /// Fetches the signed-in user again, to see a confirmation made in a
  /// browser meanwhile.
  Future<void> reload();

  Future<void> signOut();

  /// Deletes the account. [password] re-proves who is asking when the
  /// account is a password one and the sign-in is too old for the backend
  /// to accept a deletion on its own.
  Future<void> deleteAccount({String? password});
}

/// The account on this device, if any, and the ways to get or lose one.
///
/// An account is opt-in and only needed for Pro - push notifications and
/// sync - so nothing here runs until it is asked for: Firebase is started
/// at launch only when this device has signed in before, and otherwise by
/// the first sign-in attempt.
class AccountService {
  AccountService._();

  static final instance = AccountService._();

  /// Stands in for Firebase Auth in tests.
  @visibleForTesting
  static AccountBackend? Function()? backendOverride;

  AccountBackend? _firebase;

  final _users = StreamController<AccountUser?>.broadcast();
  StreamSubscription<AccountUser?>? _subscription;
  AccountUser? _user;

  /// The signed-in user, or null.
  AccountUser? get user => _user;

  /// Every change of [user], starting with nothing new.
  Stream<AccountUser?> get changes => _users.stream;

  /// Whether this build can have accounts at all. A fork or a desktop build
  /// without a Firebase project cannot.
  bool get available =>
      backendOverride != null || FirebaseService.instance.available;

  Future<AccountBackend?> _backend() async {
    final override = backendOverride;
    if (override != null) return _attach(override());
    if (!await FirebaseService.instance.start()) return null;
    return _attach(_firebase ??= FirebaseAccountBackend());
  }

  AccountBackend? _attached;

  AccountBackend? _attach(AccountBackend? backend) {
    if (backend == null || identical(backend, _attached)) return backend;
    _attached = backend;
    unawaited(_subscription?.cancel());
    _publish(backend.currentUser);
    _subscription = backend.userChanges().listen(_publish);
    return backend;
  }

  void _publish(AccountUser? user) {
    if (user == _user) return;
    _user = user;
    _users.add(user);
    unawaited(_remember(user != null));
  }

  Future<void> _remember(bool signedIn) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(kAccountSignedInPrefsKey, signedIn);
  }

  /// Picks up a sign-in from an earlier launch. Starts Firebase only when
  /// there was one.
  Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(kAccountSignedInPrefsKey) != true) return;
    try {
      await _backend();
    } catch (_) {}
  }

  Future<void> signInWithGoogle() => _run((b) => b.signInWithGoogle());

  Future<void> signInWithApple() => _run((b) => b.signInWithApple());

  Future<void> signInWithEmail(String email, String password) =>
      _run((b) => b.signInWithEmail(email.trim(), password));

  Future<void> createWithEmail(String email, String password) =>
      _run((b) => b.createWithEmail(email.trim(), password));

  Future<void> sendPasswordReset(String email) =>
      _run((b) => b.sendPasswordReset(email.trim()));

  Future<void> sendEmailVerification() =>
      _run((b) => b.sendEmailVerification());

  /// Checks again whether the address has been confirmed.
  Future<void> refresh() => _run((b) => b.reload());

  Future<void> signOut() => _run((b) => b.signOut());

  Future<void> deleteAccount({String? password}) =>
      _run((b) => b.deleteAccount(password: password));

  /// Whether Apple sign-in is offered: on iOS, where the App Store asks for
  /// it next to any other.
  Future<bool> get supportsApple async {
    try {
      return (await _backend())?.supportsApple ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _run(
    Future<void> Function(AccountBackend backend) action,
  ) async {
    final backend = await _backend();
    if (backend == null) {
      throw const AccountException(AccountFailure.unavailable);
    }
    await action(backend);
    _publish(backend.currentUser);
  }

  @visibleForTesting
  void resetForTest() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _attached = null;
    _user = null;
  }
}

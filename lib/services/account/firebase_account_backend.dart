import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../utils/platform_info.dart';
import 'account_service.dart';

/// The OAuth client Google returns an id token for, the project's web
/// client, from the build's Firebase config; and the iOS client, which iOS
/// asks for by name.
const _webClientId = String.fromEnvironment('FIREBASE_WEB_CLIENT_ID');
const _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');

/// Accounts on Firebase Auth: Google everywhere, Apple on iOS, and an email
/// with a password for anyone who wants neither.
class FirebaseAccountBackend implements AccountBackend {
  FirebaseAccountBackend();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  bool _googleReady = false;

  @override
  Stream<AccountUser?> userChanges() => _auth.userChanges().map(_toUser);

  @override
  AccountUser? get currentUser => _toUser(_auth.currentUser);

  @override
  bool get supportsApple => isIOSPlatform;

  static AccountUser? _toUser(User? user) {
    if (user == null) return null;
    final providers = {for (final info in user.providerData) info.providerId};
    return AccountUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      provider: providers.contains('google.com')
          ? AccountProvider.google
          : providers.contains('apple.com')
          ? AccountProvider.apple
          : AccountProvider.password,
    );
  }

  Future<GoogleSignIn> _google() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        serverClientId: _webClientId.isEmpty ? null : _webClientId,
        clientId: isIOSPlatform && _iosClientId.isNotEmpty
            ? _iosClientId
            : null,
      );
      _googleReady = true;
    }
    return google;
  }

  Future<OAuthCredential> _googleCredential() async {
    final google = await _google();
    try {
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AccountException(AccountFailure.unknown);
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (error) {
      throw AccountException(
        error.code == GoogleSignInExceptionCode.canceled
            ? AccountFailure.cancelled
            : AccountFailure.unknown,
      );
    }
  }

  Future<OAuthCredential> _appleCredential() async {
    final rawNonce = _nonce();
    try {
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      return OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      throw AccountException(
        error.code == AuthorizationErrorCode.canceled
            ? AccountFailure.cancelled
            : AccountFailure.unknown,
      );
    }
  }

  static String _nonce() {
    final random = Random.secure();
    return base64Url.encode([for (var i = 0; i < 32; i++) random.nextInt(256)]);
  }

  @override
  Future<void> signInWithGoogle() =>
      _guard(() async => _auth.signInWithCredential(await _googleCredential()));

  @override
  Future<void> signInWithApple() =>
      _guard(() async => _auth.signInWithCredential(await _appleCredential()));

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> createWithEmail(String email, String password) => _guard(
    () =>
        _auth.createUserWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() => _guard(() async {
    await _auth.signOut();
    if (_googleReady) await GoogleSignIn.instance.signOut();
  });

  /// A deletion the backend refuses for an old sign-in is retried once
  /// after signing in again the same way: the provider's own sheet for
  /// Google and Apple, [password] for a password account.
  @override
  Future<void> deleteAccount({String? password}) => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      if (error.code != 'requires-recent-login') rethrow;
      final credential = switch (_toUser(user)!.provider) {
        AccountProvider.google => await _googleCredential(),
        AccountProvider.apple => await _appleCredential(),
        AccountProvider.password when password != null =>
          EmailAuthProvider.credential(email: user.email!, password: password),
        AccountProvider.password => throw const AccountException(
          AccountFailure.requiresRecentLogin,
        ),
      };
      await user.reauthenticateWithCredential(credential);
      await user.delete();
    }
    if (_googleReady) await GoogleSignIn.instance.signOut();
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AccountException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AccountException(failureOf(error.code));
    }
  }

  /// The [AccountFailure] behind a Firebase Auth error code.
  static AccountFailure failureOf(String code) => switch (code) {
    'invalid-email' => AccountFailure.invalidEmail,
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' ||
    'user-disabled' => AccountFailure.wrongCredentials,
    'email-already-in-use' ||
    'account-exists-with-different-credential' => AccountFailure.emailInUse,
    'weak-password' => AccountFailure.weakPassword,
    'requires-recent-login' => AccountFailure.requiresRecentLogin,
    'network-request-failed' => AccountFailure.network,
    'too-many-requests' => AccountFailure.tooManyRequests,
    'operation-not-allowed' => AccountFailure.unavailable,
    _ => AccountFailure.unknown,
  };
}

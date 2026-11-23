import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../utils/platform_info.dart';
import '../firebase/firebase_config.dart';
import 'account_service.dart';

/// The OAuth client Google returns an id token for, the project's web
/// client, from the build's Firebase config; and the iOS client, which iOS
/// asks for by name.
const _webClientId = String.fromEnvironment('FIREBASE_WEB_CLIENT_ID');
const _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');

/// Accounts on Firebase Auth: Google and GitHub everywhere, Apple on iOS,
/// and an email with a password for anyone who wants none of them.
///
/// GitHub has no sign-in SDK of its own: Firebase opens GitHub's page in a
/// browser tab and finishes the sign-in when it comes back.
class FirebaseAccountBackend implements AccountBackend {
  /// Points browser sign-ins - GitHub's - at [FirebaseConfig.authDomain],
  /// the address registered with GitHub, when the build names one.
  FirebaseAccountBackend() {
    if (FirebaseConfig.authDomain.isNotEmpty) {
      _auth.customAuthDomain = FirebaseConfig.authDomain;
    }
  }

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
      photoUrl:
          user.photoURL ??
          user.providerData.map((info) => info.photoURL).nonNulls.firstOrNull,
      emailVerified: user.emailVerified,
      provider: providers.contains('google.com')
          ? AccountProvider.google
          : providers.contains('apple.com')
          ? AccountProvider.apple
          : providers.contains('github.com')
          ? AccountProvider.github
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
  Future<void> signInWithGitHub() =>
      _guard(() => _auth.signInWithProvider(GithubAuthProvider()));

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  /// Creates the account and mails the link that confirms the address.
  @override
  Future<void> createWithEmail(String email, String password) =>
      _guard(() async {
        final created = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await created.user?.sendEmailVerification();
      });

  @override
  Future<void> sendEmailVerification() =>
      _guard(() async => _auth.currentUser?.sendEmailVerification());

  @override
  Future<void> reload() => _guard(() async => _auth.currentUser?.reload());

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
  /// Google and Apple, GitHub's page for GitHub, [password] for a password
  /// account.
  @override
  Future<AccountToken?> idToken({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final result = await user.getIdTokenResult(force);
    final token = result.token;
    final expires = result.expirationTime;
    if (token == null || expires == null) return null;
    return (
      token: token,
      expires: expires,
      claims: Map<String, Object?>.from(result.claims ?? const {}),
    );
  }

  @override
  bool get signsInThroughBrowser => false;

  @override
  Future<void> signInThroughBrowser(
    void Function(BrowserSignIn link) show, {
    required bool Function() cancelled,
  }) => Future.error(const AccountException(AccountFailure.unavailable));

  @override
  Future<void> deleteAccount({String? password}) => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      if (error.code != 'requires-recent-login') rethrow;
      await _reauthenticate(user, password);
      await user.delete();
    }
    if (_googleReady) await GoogleSignIn.instance.signOut();
  });

  /// Signs [user] in again the way they signed in before, for an action
  /// the backend only allows right after a sign-in.
  Future<void> _reauthenticate(User user, String? password) async {
    switch (_toUser(user)!.provider) {
      case AccountProvider.google:
        await user.reauthenticateWithCredential(await _googleCredential());
      case AccountProvider.apple:
        await user.reauthenticateWithCredential(await _appleCredential());
      case AccountProvider.github:
        await user.reauthenticateWithProvider(GithubAuthProvider());
      case AccountProvider.password when password != null:
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        );
      case AccountProvider.password:
        throw const AccountException(AccountFailure.requiresRecentLogin);
    }
  }

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
    'web-context-canceled' ||
    'web-context-cancelled' ||
    'canceled' => AccountFailure.cancelled,
    _ => AccountFailure.unknown,
  };
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';
import '../app/project_urls.dart';
import '../security/secret_cipher.dart';
import 'account_service.dart';

/// The Firebase project's web API key, for Firebase Auth's REST API on a
/// computer. Not a secret - every web page of the project carries it - but
/// it comes in at build time like the rest of the Firebase configuration.
const kFirebaseWebApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');

/// Where the functions that sign a computer in live.
const kLinkStartUrl =
    'https://europe-central2-termphin-hexeosoft.cloudfunctions.net/linkStart';
const kLinkFinishUrl =
    'https://europe-central2-termphin-hexeosoft.cloudfunctions.net/linkFinish';

/// One HTTP call's answer: its status and its JSON body (empty when there
/// was none).
typedef RestAnswer = ({int status, Map<String, Object?> body});

/// Posts [body] as JSON to [url]. Stands in for the network in tests.
typedef RestPost =
    Future<RestAnswer> Function(Uri url, Map<String, Object?> body);

/// The signed-in session kept on this computer: who, and the tokens that
/// prove it.
@immutable
class RestSession {
  const RestSession({
    required this.user,
    required this.refreshToken,
    this.idToken,
    this.expires,
  });

  final AccountUser user;
  final String refreshToken;
  final String? idToken;
  final DateTime? expires;

  Map<String, Object?> toJson() => {
    'uid': user.uid,
    'provider': user.provider.name,
    'email': user.email,
    'displayName': user.displayName,
    'photoUrl': user.photoUrl,
    'emailVerified': user.emailVerified,
    'refreshToken': refreshToken,
  };

  static RestSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'];
    final refresh = json['refreshToken'];
    if (uid is! String || refresh is! String) return null;
    return RestSession(
      user: AccountUser(
        uid: uid,
        provider: AccountProvider.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => AccountProvider.password,
        ),
        email: json['email'] as String?,
        displayName: json['displayName'] as String?,
        photoUrl: json['photoUrl'] as String?,
        emailVerified: json['emailVerified'] as bool? ?? true,
      ),
      refreshToken: refresh,
    );
  }
}

/// The claims inside a Firebase ID token: its payload, read without checking
/// the signature - the server checks that; the app only reads what it says
/// about itself, such as Pro.
Map<String, Object?> idTokenClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return const {};
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final claims = jsonDecode(payload);
    return claims is Map<String, Object?> ? claims : const {};
  } on FormatException {
    return const {};
  }
}

/// How a provider id from Firebase's account lookup reads to the app.
AccountProvider providerFromId(String? id) => switch (id) {
  'google.com' => AccountProvider.google,
  'apple.com' => AccountProvider.apple,
  'github.com' => AccountProvider.github,
  _ => AccountProvider.password,
};

/// The account on a computer, where Firebase's plugins do not run: Firebase
/// Auth through its REST API, signed in by a code confirmed on the account
/// page (`app.termphin.dev/link`) rather than by a provider's own sign-in,
/// which needs a phone's or a browser's machinery.
///
/// Signing in: [signInThroughBrowser] asks `linkStart` for a code, with the
/// hash of a secret only this computer holds; the user confirms the code on
/// the account page, signed in there with any provider; polling
/// `linkFinish` with the secret then hands back a custom token, which
/// Firebase Auth trades for the account's own ID and refresh tokens. The
/// refresh token is kept sealed ([SecretCipher]) so the next launch is
/// signed in too. Everything else a phone does in the app - changing the
/// password, deleting the account - happens on the account page.
class RestAccountBackend implements AccountBackend {
  RestAccountBackend({
    required this.apiKey,
    RestPost? post,
    SecretCipher? cipher,
    Duration pollEvery = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _post = post ?? _httpPost,
       _cipher = cipher ?? SecretCipher.instance,
       _pollEvery = pollEvery,
       _now = now ?? DateTime.now;

  final String apiKey;
  final RestPost _post;
  final SecretCipher _cipher;
  final Duration _pollEvery;
  final DateTime Function() _now;

  static const _storeKey = 'rest_account_session';
  static const _storeAad = 'rest-account-session-v1';

  /// Whether this build can sign in this way: a computer with the web API
  /// key built in.
  static bool get configured =>
      isDesktopPlatform && kFirebaseWebApiKey.isNotEmpty;

  final _changes = StreamController<AccountUser?>.broadcast();
  RestSession? _session;
  Future<RestSession>? _refreshing;

  /// Reads the session an earlier launch kept, if any.
  Future<void> restore() async {
    final stored = (await SharedPreferences.getInstance()).getString(_storeKey);
    if (stored == null) return;
    final opened = await _cipher.open(stored, aad: _storeAad);
    if (opened == null) return;
    try {
      _session = RestSession.fromJson(jsonDecode(opened));
    } on FormatException {
      _session = null;
    }
  }

  Future<void> _save(RestSession? session) async {
    _session = session;
    final preferences = await SharedPreferences.getInstance();
    if (session == null) {
      await preferences.remove(_storeKey);
    } else {
      await preferences.setString(
        _storeKey,
        await _cipher.seal(jsonEncode(session.toJson()), aad: _storeAad),
      );
    }
    _changes.add(session?.user);
  }

  @override
  Stream<AccountUser?> userChanges() => _changes.stream;

  @override
  AccountUser? get currentUser => _session?.user;

  @override
  bool get signsInThroughBrowser => true;

  @override
  Future<void> signInThroughBrowser(
    void Function(BrowserSignIn link) show, {
    required bool Function() cancelled,
  }) async {
    final secret = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final started = await _call(Uri.parse(kLinkStartUrl), {
      'secretHash': sha256.convert(utf8.encode(secret)).toString(),
      'device': 'Termphin on ${_platformName()}',
    });
    final linkId = started.body['linkId'];
    final code = started.body['code'];
    final expiresIn = (started.body['expiresIn'] as num?)?.toInt() ?? 600;
    if (started.status != 200 || linkId is! String || code is! String) {
      throw const AccountException(AccountFailure.unavailable);
    }
    show((
      code: code,
      page: Uri.parse(
        '${ProjectUrls.accountPage}/link',
      ).replace(queryParameters: {'code': code}),
    ));
    final deadline = _now().add(Duration(seconds: expiresIn));
    while (true) {
      if (cancelled()) throw const AccountException(AccountFailure.cancelled);
      if (_now().isAfter(deadline)) {
        throw const AccountException(AccountFailure.cancelled);
      }
      await Future<void>.delayed(_pollEvery);
      if (cancelled()) throw const AccountException(AccountFailure.cancelled);
      final answer = await _call(Uri.parse(kLinkFinishUrl), {
        'linkId': linkId,
        'secret': secret,
      });
      if (answer.status == 202) continue;
      final customToken = answer.body['customToken'];
      if (answer.status == 200 && customToken is String) {
        await _signInWithCustomToken(customToken);
        return;
      }
      if (answer.status == 410) {
        throw const AccountException(AccountFailure.cancelled);
      }
      throw const AccountException(AccountFailure.unknown);
    }
  }

  Future<void> _signInWithCustomToken(String customToken) async {
    final answer = await _call(_identity('accounts:signInWithCustomToken'), {
      'token': customToken,
      'returnSecureToken': true,
    });
    final idToken = answer.body['idToken'];
    final refreshToken = answer.body['refreshToken'];
    if (answer.status != 200 || idToken is! String || refreshToken is! String) {
      throw const AccountException(AccountFailure.unknown);
    }
    final user = await _lookup(idToken);
    await _save(
      RestSession(
        user: user,
        refreshToken: refreshToken,
        idToken: idToken,
        expires: _expiresAt(answer.body['expiresIn']),
      ),
    );
  }

  /// Who [idToken] belongs to, as Firebase Auth has them now.
  Future<AccountUser> _lookup(String idToken) async {
    final answer = await _call(_identity('accounts:lookup'), {
      'idToken': idToken,
    });
    final users = answer.body['users'];
    if (answer.status != 200 || users is! List || users.isEmpty) {
      throw const AccountException(AccountFailure.unknown);
    }
    final found = users.first as Map<String, Object?>;
    final providers = found['providerUserInfo'];
    final providerId = providers is List && providers.isNotEmpty
        ? (providers.first as Map)['providerId'] as String?
        : null;
    return AccountUser(
      uid: found['localId'] as String? ?? '',
      provider: providerFromId(providerId),
      email: found['email'] as String?,
      displayName: found['displayName'] as String?,
      photoUrl: found['photoUrl'] as String?,
      emailVerified: found['emailVerified'] as bool? ?? false,
    );
  }

  @override
  Future<AccountToken?> idToken({bool force = false}) async {
    final session = _session;
    if (session == null) return null;
    final expires = session.expires;
    final token = session.idToken;
    if (!force &&
        token != null &&
        expires != null &&
        expires.difference(_now()) > const Duration(minutes: 1)) {
      return (token: token, expires: expires, claims: idTokenClaims(token));
    }
    final fresh = await (_refreshing ??= _refresh(
      session,
    ).whenComplete(() => _refreshing = null));
    return (
      token: fresh.idToken!,
      expires: fresh.expires!,
      claims: idTokenClaims(fresh.idToken!),
    );
  }

  /// Trades the refresh token for a new ID token. A refresh token Firebase
  /// no longer takes - the account was deleted, or its password changed -
  /// signs this computer out.
  Future<RestSession> _refresh(RestSession session) async {
    final answer = await _call(
      Uri.parse(
        'https://securetoken.googleapis.com/v1/token',
      ).replace(queryParameters: {'key': apiKey}),
      {'grant_type': 'refresh_token', 'refresh_token': session.refreshToken},
    );
    final idToken = answer.body['id_token'];
    final refreshToken = answer.body['refresh_token'];
    if (answer.status == 400) {
      await _save(null);
      throw const AccountException(AccountFailure.requiresRecentLogin);
    }
    if (answer.status != 200 || idToken is! String || refreshToken is! String) {
      throw const AccountException(AccountFailure.network);
    }
    final fresh = RestSession(
      user: session.user,
      refreshToken: refreshToken,
      idToken: idToken,
      expires: _expiresAt(answer.body['expires_in']),
    );
    if (refreshToken != session.refreshToken) {
      await _save(fresh);
    } else {
      _session = fresh;
    }
    return fresh;
  }

  @override
  Future<void> reload() async {
    final token = await idToken(force: true);
    final current = _session;
    if (token == null || current == null) return;
    final user = await _lookup(token.token);
    if (user == current.user) return;
    await _save(
      RestSession(
        user: user,
        refreshToken: current.refreshToken,
        idToken: current.idToken,
        expires: current.expires,
      ),
    );
  }

  @override
  Future<void> signOut() => _save(null);

  @override
  bool get supportsApple => false;

  @override
  Future<void> signInWithGoogle() => _onTheAccountPage();

  @override
  Future<void> signInWithApple() => _onTheAccountPage();

  @override
  Future<void> signInWithGitHub() => _onTheAccountPage();

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _onTheAccountPage();

  @override
  Future<void> createWithEmail(String email, String password) =>
      _onTheAccountPage();

  @override
  Future<void> sendPasswordReset(String email) => _onTheAccountPage();

  @override
  Future<void> sendEmailVerification() => _onTheAccountPage();

  @override
  Future<void> deleteAccount({String? password}) => _onTheAccountPage();

  /// What a computer leaves to the account page: it cannot do it here.
  Future<void> _onTheAccountPage() =>
      Future.error(const AccountException(AccountFailure.unavailable));

  Uri _identity(String method) => Uri.parse(
    'https://identitytoolkit.googleapis.com/v1/$method',
  ).replace(queryParameters: {'key': apiKey});

  DateTime _expiresAt(Object? seconds) =>
      _now().add(Duration(seconds: int.tryParse('$seconds') ?? 3600));

  Future<RestAnswer> _call(Uri url, Map<String, Object?> body) async {
    try {
      return await _post(url, body);
    } on SocketException {
      throw const AccountException(AccountFailure.network);
    } on TimeoutException {
      throw const AccountException(AccountFailure.network);
    } on HttpException {
      throw const AccountException(AccountFailure.network);
    }
  }

  static String _platformName() {
    if (isMacOSPlatform) return 'macOS';
    if (isWindowsPlatform) return 'Windows';
    return 'Linux';
  }

  static Future<RestAnswer> _httpPost(
    Uri url,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await response.transform(utf8.decoder).join();
      Object? decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      return (
        status: response.statusCode,
        body: decoded is Map<String, Object?> ? decoded : <String, Object?>{},
      );
    } finally {
      client.close();
    }
  }
}

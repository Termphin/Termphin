import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/services/account/rest_account_backend.dart';
import 'package:termphin/services/security/secret_cipher.dart';

import '../../support/fake_master_key_store.dart';

/// A JWT whose payload is [claims]; the signature is never checked here.
String jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(claims)}.sig';
}

/// Firebase and the link functions, answering from a script of replies by
/// path, and recording every call.
class FakeServer {
  final calls = <(String, Map<String, Object?>)>[];
  final replies = <String, List<RestAnswer>>{};

  void reply(String path, int status, [Map<String, Object?> body = const {}]) =>
      (replies[path] ??= []).add((status: status, body: body));

  Future<RestAnswer> post(Uri url, Map<String, Object?> body) async {
    final path = url.path.split('/').last;
    calls.add((path, body));
    final queue = replies[path];
    if (queue == null || queue.isEmpty) {
      return (status: 500, body: const <String, Object?>{});
    }
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }
}

void main() {
  late FakeServer server;
  late DateTime now;
  late SecretCipher cipher;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeServer();
    cipher = SecretCipher(store: FakeMasterKeyStore());
    now = DateTime(2026, 11, 23, 22);
  });

  RestAccountBackend backend() => RestAccountBackend(
    apiKey: 'web-key',
    post: server.post,
    cipher: cipher,
    pollEvery: Duration.zero,
    now: () => now,
  );

  void signInScript({int pendingPolls = 1}) {
    server.reply('linkStart', 200, {
      'linkId': 'link12345678',
      'code': 'ABCD-EFGH',
      'expiresIn': 600,
    });
    for (var i = 0; i < pendingPolls; i++) {
      server.reply('linkFinish', 202, {'pending': true});
    }
    server.reply('linkFinish', 200, {'customToken': 'custom'});
    server.reply('accounts:signInWithCustomToken', 200, {
      'idToken': jwt({'pro': true}),
      'refreshToken': 'refresh-1',
      'expiresIn': '3600',
    });
    server.reply('accounts:lookup', 200, {
      'users': [
        {
          'localId': 'u1',
          'email': 'me@example.com',
          'emailVerified': true,
          'providerUserInfo': [
            {'providerId': 'github.com'},
          ],
        },
      ],
    });
  }

  test('signs in with a code confirmed on the account page', () async {
    signInScript();
    final account = backend();
    BrowserSignIn? shown;
    await account.signInThroughBrowser(
      (link) => shown = link,
      cancelled: () => false,
    );

    expect(shown!.code, 'ABCD-EFGH');
    expect(
      shown!.page.toString(),
      'https://app.termphin.dev/link?code=ABCD-EFGH',
    );
    expect(account.currentUser!.uid, 'u1');
    expect(account.currentUser!.provider, AccountProvider.github);

    final start = server.calls.first.$2;
    final finish = server.calls.firstWhere((c) => c.$1 == 'linkFinish').$2;
    expect(start['secretHash'], hasLength(64));
    expect(start.containsKey('secret'), isFalse);
    expect(finish['secret'], isNot(start['secretHash']));
  });

  test('reads Pro from the token it signed in with', () async {
    signInScript(pendingPolls: 0);
    final account = backend();
    await account.signInThroughBrowser((_) {}, cancelled: () => false);

    final token = await account.idToken();
    expect(token!.claims['pro'], true);
    expect(server.calls.where((c) => c.$1 == 'token'), isEmpty);
  });

  test('stays signed in across launches, refreshing the token', () async {
    signInScript(pendingPolls: 0);
    await backend().signInThroughBrowser((_) {}, cancelled: () => false);

    final next = backend();
    await next.restore();
    expect(next.currentUser!.email, 'me@example.com');

    server.reply('token', 200, {
      'id_token': jwt({'pro': false}),
      'refresh_token': 'refresh-1',
      'expires_in': '3600',
    });
    final token = await next.idToken();
    expect(token!.claims['pro'], false);
    expect(
      server.calls.lastWhere((c) => c.$1 == 'token').$2['refresh_token'],
      'refresh-1',
    );
  });

  test('a refresh token Firebase refuses signs the computer out', () async {
    signInScript(pendingPolls: 0);
    final account = backend();
    await account.signInThroughBrowser((_) {}, cancelled: () => false);
    server.reply('token', 400, {'error': 'TOKEN_EXPIRED'});

    await expectLater(
      account.idToken(force: true),
      throwsA(isA<AccountException>()),
    );
    expect(account.currentUser, isNull);
    final next = backend();
    await next.restore();
    expect(next.currentUser, isNull);
  });

  test('giving up while waiting signs nothing in', () async {
    signInScript(pendingPolls: 3);
    final account = backend();

    await expectLater(
      account.signInThroughBrowser(
        (_) {},
        cancelled: () =>
            server.calls.where((c) => c.$1 == 'linkFinish').length >= 2,
      ),
      throwsA(
        isA<AccountException>().having(
          (e) => e.failure,
          'failure',
          AccountFailure.cancelled,
        ),
      ),
    );
    expect(account.currentUser, isNull);
  });

  test('an expired code ends the wait', () async {
    server.reply('linkStart', 200, {
      'linkId': 'link12345678',
      'code': 'ABCD-EFGH',
      'expiresIn': 600,
    });
    server.reply('linkFinish', 410);

    await expectLater(
      backend().signInThroughBrowser((_) {}, cancelled: () => false),
      throwsA(isA<AccountException>()),
    );
  });

  test('signing out forgets the session', () async {
    signInScript(pendingPolls: 0);
    final account = backend();
    await account.signInThroughBrowser((_) {}, cancelled: () => false);
    await account.signOut();

    expect(account.currentUser, isNull);
    expect(await account.idToken(), isNull);
  });

  test('reads claims from a token without checking its signature', () {
    expect(idTokenClaims(jwt({'pro': true, 'proUntil': 5}))['proUntil'], 5);
    expect(idTokenClaims('not-a-token'), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/assistant/assistant_redactor.dart';
import 'package:termphin/services/assistant/assistant_secret_rules.dart';

void main() {
  AssistantRedactor redactor() => AssistantRedactor(
    hosts: ['web-01.shop-company.pl', 'web-01'],
    users: ['mbadyl', 'root'],
  );

  test('hides the server, its addresses and users, and keeps loopback', () {
    final r = redactor();
    final hidden = r.hide(
      'mbadyl@web-01:~\$ ssh deploy@web-01.shop-company.pl\n'
      'upstream: "http://127.0.0.1:3000/", client: 203.0.113.7, server: 10.0.0.5\n'
      'cd /home/mbadyl/shop && ls /root',
    );
    expect(hidden, isNot(contains('mbadyl')));
    expect(hidden, isNot(contains('web-01')));
    expect(hidden, isNot(contains('shop-company')));
    expect(hidden, isNot(contains('203.0.113.7')));
    expect(hidden, isNot(contains('10.0.0.5')));
    expect(hidden, contains('127.0.0.1:3000'));
    expect(hidden, contains('/root'));
    expect(hidden, contains('USER_1@HOST_'));
    expect(
      r.reveal(hidden),
      contains('mbadyl@web-01:~\$ ssh deploy@web-01.shop-company.pl'),
    );
  });

  test('a value keeps its placeholder through the conversation', () {
    final r = redactor();
    final first = r.hide('client 203.0.113.7 and 198.51.100.2');
    final second = r.hide('again 198.51.100.2 then 203.0.113.7');
    expect(first, 'client IP_1 and IP_2');
    expect(second, 'again IP_2 then IP_1');
    expect(r.hide('client 203.0.113.7 and 198.51.100.2'), first);
  });

  test('hides secrets so they never leave, and puts them back to run', () {
    final r = redactor();
    final stripe = ['sk', 'live', '51HxAbCdEfGhIjKlMnOpQrSt'].join('_');
    const token =
        'abcd'
        '1234'
        'efgh';
    final env =
        'DATABASE_URL=postgres://shop:hunter2pass@db.internal:5432/shop\n'
        'STRIPE_SECRET_KEY=$stripe\n'
        'API_TOKEN="$token"\n'
        'Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345\n'
        'aws AKIAIOSFODNN7EXAMPLE github ghp_0123456789abcdefghijklmnopqrstuvwxyzAB\n'
        '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----';
    final hidden = r.hide(env);
    for (final secret in [
      'hunter2pass',
      stripe,
      token,
      'abcdefghijklmnopqrstuvwxyz012345',
      'AKIAIOSFODNN7EXAMPLE',
      'ghp_0123456789abcdefghijklmnopqrstuvwxyzAB',
      'b3BlbnNzaC1rZXktdjEAAAAA',
    ]) {
      expect(hidden, isNot(contains(secret)), reason: secret);
    }
    expect(hidden, contains('postgres://shop:[SECRET_'));
    expect(r.reveal(hidden), env);
  });

  test('hides provider tokens inspired by Gitleaks rules', () {
    final r = redactor();
    final anthropic = [
      'sk',
      'ant',
      'api03',
      '0123456789abcdefGHIJKLMNOP',
    ].join('-');
    final gitlab = ['glpat', '0123456789abcdefGHIJ'].join('-');
    final npm = ['npm', '0123456789abcdefghijklmnopqrstuvwxyz'].join('_');
    final sendgrid = [
      'SG',
      '0123456789abcdef',
      '0123456789abcdefGHIJ',
    ].join('.');
    final digitalOcean = [
      'dop',
      'v1',
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    ].join('_');
    final huggingFace = ['hf', '0123456789abcdefGHIJKLMN'].join('_');
    final slackWebhook = [
      'https://hooks.slack.com/services',
      'T00000001',
      'B00000002',
      '0123456789abcdefGHIJ',
    ].join('/');
    final supabase = [
      'sb',
      'secret',
      ['01234567', '89abcdef', 'GHIJKLMN'].join(),
    ].join('_');
    final vault = ['hvs', '0123456789abcdefGHIJKLMN'].join('.');
    final telegram = [
      '123456789',
      'AA0123456789abcdefGHIJKLMNOPQRSTUV',
    ].join(':');

    final text = [
      anthropic,
      gitlab,
      npm,
      sendgrid,
      digitalOcean,
      huggingFace,
      slackWebhook,
      supabase,
      vault,
      telegram,
    ].join('\n');
    final hidden = r.hide(text);
    for (final secret in [
      anthropic,
      gitlab,
      npm,
      sendgrid,
      digitalOcean,
      huggingFace,
      slackWebhook,
      supabase,
      vault,
      telegram,
    ]) {
      expect(hidden, isNot(contains(secret)), reason: secret);
    }
    expect(r.reveal(hidden), text);
  });

  test('handles JSON assignments, single quotes, and key-value collisions', () {
    final r = redactor();
    const input =
        '{"password": "my secret 123", "token": null, "api_key": "\${API_KEY}"}\n'
        'MY_PASSWORD=PASSWORD\n'
        "API_TOKEN='secret-value-1'";
    final hidden = r.hide(input);
    expect(hidden, isNot(contains('my secret 123')));
    expect(hidden, isNot(contains('secret-value-1')));
    expect(hidden, contains('MY_PASSWORD=[SECRET_'));
    expect(hidden, contains('"token": null'));
    expect(hidden, contains(r'"api_key": "${API_KEY}"'));
    expect(r.reveal(hidden), input);
  });

  test('uses contextual Shannon entropy without redacting harmless config', () {
    final r = redactor();
    expect(shannonEntropy('aaaa'), 0);
    expect(shannonEntropy('0123456789abcdef'), 4.0);

    final signingKey = ['9f8e7d6c', '5b4a3f2e', '1d0c9b8a', '7f6e5d4c'].join();
    final input =
        'SIGNING_KEY=$signingKey\n'
        'HMAC_SALT="Xy9!kLm2#Pq7vR4z"\n'
        'PUBLIC_KEY=/etc/ssh/ssh_host_ed25519_key.pub\n'
        'COOKIE_DOMAIN=web-01.shop-company.pl\n'
        'SESSION_DRIVER=redis_cluster\n'
        'AUTH_URL=https://accounts.example.com/login\n'
        'SSH_KEY=ssh-ed25519';
    final hidden = r.hide(input);

    expect(hidden, isNot(contains(signingKey)));
    expect(hidden, isNot(contains('Xy9!kLm2#Pq7vR4z')));
    expect(hidden, contains('PUBLIC_KEY=/etc/ssh/ssh_host_ed25519_key.pub'));
    expect(hidden, contains('COOKIE_DOMAIN=HOST_1'));
    expect(hidden, contains('SESSION_DRIVER=redis_cluster'));
    expect(hidden, contains('AUTH_URL=https://accounts.example.com/login'));
    expect(hidden, contains('SSH_KEY=ssh-ed25519'));
    expect(r.reveal(hidden), input);
  });

  test('a placeholder the model sends back is not hidden again', () {
    final r = redactor();
    final hidden = r.hide('DB_PASSWORD=supersecret');
    expect(hidden, 'DB_PASSWORD=[SECRET_1]');
    expect(r.hide(hidden), hidden);
    expect(
      r.reveal('echo DB_PASSWORD=[SECRET_1] on HOST_9'),
      'echo DB_PASSWORD=supersecret on HOST_9',
    );
  });

  test('reveal handles case differences and Markdown-escaped underscores', () {
    final r = redactor();
    r.hide('mbadyl@web-01 DB_PASSWORD=supersecret');
    expect(
      r.reveal(
        r'Check host\_2 as user\_1 with [secret\_1] and [secret_1], keep HOST_9',
      ),
      'Check web-01 as mbadyl with supersecret and supersecret, keep HOST_9',
    );
  });

  test('emails, IPv6, and MAC addresses', () {
    final r = redactor();
    final hidden = r.hide(
      'owner ops@shop-company.pl from 2001:db8::1 and fe80::1ff:fe23:4567:890a, local ::1 at 12:02:41\n'
      'link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff',
    );
    expect(
      hidden,
      'owner EMAIL_1 from IP_1 and IP_2, local ::1 at 12:02:41\n'
      'link/ether MAC_1 brd ff:ff:ff:ff:ff:ff',
    );
    expect(
      r.reveal(hidden),
      'owner ops@shop-company.pl from 2001:db8::1 and fe80::1ff:fe23:4567:890a, local ::1 at 12:02:41\n'
      'link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff',
    );
  });

  test('hides Windows home paths and keeps common account names', () {
    final r = AssistantRedactor(users: ['root', 'ubuntu', 'me']);
    expect(
      r.hide(r'root ubuntu me /home/ubuntu C:\Users\Public C:\Users\alice\app'),
      r'root ubuntu me /home/ubuntu C:\Users\Public C:\Users\USER_1\app',
    );
  });
}

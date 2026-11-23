import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/assistant/assistant_redactor.dart';

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

  test('emails and IPv6 addresses', () {
    final r = redactor();
    final hidden = r.hide(
      'owner ops@shop-company.pl from 2001:db8::1 and fe80::1ff:fe23:4567:890a, local ::1 at 12:02:41',
    );
    expect(hidden, 'owner EMAIL_1 from IP_1 and IP_2, local ::1 at 12:02:41');
  });

  test('common account names stay', () {
    final r = AssistantRedactor(users: ['root', 'ubuntu', 'me']);
    expect(
      r.hide('root ubuntu me /home/ubuntu'),
      'root ubuntu me /home/ubuntu',
    );
  });
}

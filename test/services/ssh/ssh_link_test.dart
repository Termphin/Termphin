import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/ssh/ssh_link.dart';

/// What an `ssh://` link is allowed to turn into.
///
/// The parser is strict on purpose: a link is something somebody else can send
/// you, so every case below where it returns null is a case where guessing
/// would put the user in front of a machine they did not mean to reach.
void main() {
  group('a usable link', () {
    test('a bare host defaults to port 22 and no username', () {
      final link = parseSshLink('ssh://example.com');

      expect(link, isNotNull);
      expect(link!.host, 'example.com');
      expect(link.port, 22);
      expect(link.user, isNull);
    });

    test('a username and port are both taken', () {
      final link = parseSshLink('ssh://deploy@example.com:2222');

      expect(link!.user, 'deploy');
      expect(link.host, 'example.com');
      expect(link.port, 2222);
    });

    test('the scheme is matched whatever its case', () {
      expect(parseSshLink('SSH://example.com')?.host, 'example.com');
    });

    test('an IPv6 literal keeps its address and loses the brackets', () {
      final link = parseSshLink('ssh://[2001:db8::1]:22');

      expect(link!.host, '2001:db8::1');
      expect(link.port, 22);
    });

    test('a bare trailing slash is not a path', () {
      expect(parseSshLink('ssh://example.com/')?.host, 'example.com');
    });
  });

  group('a password in the link', () {
    test('is dropped rather than parsed, and the user survives', () {
      final link = parseSshLink('ssh://deploy:hunter2@example.com');

      expect(link, isNotNull);
      expect(link!.user, 'deploy');
      expect(link.host, 'example.com');
      expect(link.toString(), isNot(contains('hunter2')));
    });
  });

  group('a link that cannot be trusted is refused outright', () {
    test('another scheme is not ours to open', () {
      expect(parseSshLink('http://example.com'), isNull);
      expect(parseSshLink('sftp://example.com'), isNull);
    });

    test('a missing host has nothing to connect to', () {
      expect(parseSshLink('ssh://'), isNull);
      expect(parseSshLink('ssh://deploy@'), isNull);
    });

    test('a port outside 1..65535 fails the link instead of becoming 22', () {
      expect(parseSshLink('ssh://example.com:0'), isNull);
      expect(parseSshLink('ssh://example.com:99999'), isNull);
    });

    test('a path, query or fragment means this is not a plain host', () {
      expect(parseSshLink('ssh://example.com/path'), isNull);
      expect(parseSshLink('ssh://example.com?x=1'), isNull);
      expect(parseSshLink('ssh://example.com#frag'), isNull);
    });

    test('nonsense is refused rather than thrown on', () {
      expect(parseSshLink(''), isNull);
      expect(parseSshLink('not a url at all'), isNull);
      expect(parseSshLink('ssh:/example.com'), isNull);
    });
  });

  group('what someone types to add a machine', () {
    SshLink? parse(String raw) => parseSshTarget(raw);

    test('user@host is what it looks like', () {
      expect(
        parse('alice@devbox'),
        const SshLink(host: 'devbox', user: 'alice'),
      );
    });

    test('a bare host has no user yet', () {
      expect(parse('  example.com '), const SshLink(host: 'example.com'));
    });

    test('a port after a colon is taken', () {
      expect(
        parse('root@10.0.0.5:2222'),
        const SshLink(host: '10.0.0.5', port: 2222, user: 'root'),
      );
    });

    test('a pasted ssh command is read the way ssh reads it', () {
      expect(
        parse('ssh deploy@web.example.com'),
        const SshLink(host: 'web.example.com', user: 'deploy'),
      );
      expect(
        parse('ssh -p 2202 deploy@web'),
        const SshLink(host: 'web', port: 2202, user: 'deploy'),
      );
      expect(
        parse('ssh deploy@web -p 2202'),
        const SshLink(host: 'web', port: 2202, user: 'deploy'),
      );
      expect(
        parse('ssh -l deploy web'),
        const SshLink(host: 'web', user: 'deploy'),
      );
    });

    test(
      'flags and their arguments are stepped over, not taken as the host',
      () {
        expect(
          parse(
            'ssh -A -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no ops@db',
          ),
          const SshLink(host: 'db', user: 'ops'),
        );
      },
    );

    test('an ssh:// link still works here', () {
      expect(
        parse('ssh://ops@db:2200'),
        const SshLink(host: 'db', port: 2200, user: 'ops'),
      );
    });

    test('an IPv6 address keeps its colons', () {
      expect(
        parse('ops@[fd00::1]:2222'),
        const SshLink(host: 'fd00::1', port: 2222, user: 'ops'),
      );
      expect(parse('ops@fd00::1'), const SshLink(host: 'fd00::1', user: 'ops'));
    });

    test('what is not a machine is refused', () {
      expect(parse(''), isNull);
      expect(parse('ssh'), isNull);
      expect(parse('@host'), isNull);
      expect(parse('user@'), isNull);
      expect(parse('two words'), isNull);
      expect(parse('ops@db:99999'), isNull);
      expect(parse('ssh -p'), isNull);
      expect(parse('ssh one two'), isNull);
    });
  });
}

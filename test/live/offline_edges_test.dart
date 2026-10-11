import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/utils/sftp_path.dart';

/// Boundaries found while bug-hunting against a live server, each one a case
/// the shipped code used to get wrong.
void main() {
  group('windows sftp paths', () {
    test('round-trips a drive root', () {
      expect(sftpPathToDisplay('/C:'), r'C:\');
      expect(displayPathToSftp(r'C:\'), '/C:');
      expect(sftpPathToDisplay('/C:/Users/me'), r'C:\Users\me');
      expect(displayPathToSftp(r'C:\Users\me'), '/C:/Users/me');
    });

    test('converts a bare drive typed without a separator', () {
      expect(displayPathToSftp('C:'), '/C:');
    });

    test('converts the forward-slash spelling Windows also accepts', () {
      expect(displayPathToSftp('C:/Users/me'), '/C:/Users/me');
      expect(displayPathToSftp('C:/'), '/C:');
    });

    test('a POSIX file with a backslash in its name survives', () {
      expect(sftpPathToDisplay(r'/home/me/back\slash'), r'/home/me/back\slash');
      expect(displayPathToSftp(r'/home/me/back\slash'), r'/home/me/back\slash');
    });
  });

  group('session names', () {
    test('rejects everything that would need shell quoting', () {
      for (final name in [
        "a'; rm -rf ~; echo '",
        'a b',
        r'a$(id)',
        'a`id`',
        'a\nb',
        '../../etc/passwd',
        '',
      ]) {
        expect(SessionTab.validateName(name), isNotNull, reason: name);
      }
    });

    test('rejects a padded name rather than sending it untrimmed', () {
      expect(SessionTab.validateName('  padded  '), 'nameInvalid');
      expect(SessionTab.validateName('padded'), isNull);
    });

    test('rejects a name too long to be a directory on the server', () {
      expect(SessionTab.validateName('a' * SessionTab.maxNameLength), isNull);
      expect(
        SessionTab.validateName('a' * (SessionTab.maxNameLength + 1)),
        'nameInvalid',
      );
    });
  });

  group('connection candidates', () {
    test('parses IPv6 with and without a bracketed port', () {
      expect(SshEndpoint.parse('[::1]:2222', defaultPort: 22).port, 2222);
      expect(SshEndpoint.parse('::1', defaultPort: 22).host, '::1');
      expect(SshEndpoint.parse('host:2222', defaultPort: 22).port, 2222);
      expect(SshEndpoint.parse('host', defaultPort: 22).port, 22);
    });

    test('strips the brackets from a bracketed IPv6 with no port', () {
      final endpoint = SshEndpoint.parse('[::1]', defaultPort: 22);
      expect(endpoint.host, '::1');
      expect(endpoint.port, 22);
    });

    test('drops blank fallback entries', () {
      final profile = SshProfile(
        id: 'x',
        name: 'x',
        host: 'a',
        port: 22,
        username: 'u',
        authMethod: AuthMethod.none,
        fallbackHosts: const ['', '   ', 'b'],
        createdAt: DateTime.now(),
      );
      expect(profile.connectionCandidates, ['a', 'b']);
    });
  });
}

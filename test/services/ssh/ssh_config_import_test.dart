import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/ssh_config_import.dart';

void main() {
  group('parseSshConfig', () {
    test('reads each host with its name, user, port and key', () {
      final hosts = parseSshConfig('''
# work
Host web
  HostName 10.0.0.4
  User root
  Port 2222
  IdentityFile ~/.ssh/work

Host pi
  HostName=raspberry.lan
''');

      expect(hosts.map((h) => h.alias), ['web', 'pi']);
      expect(hosts[0].hostName, '10.0.0.4');
      expect(hosts[0].user, 'root');
      expect(hosts[0].port, 2222);
      expect(hosts[0].identityFile, '~/.ssh/work');
      expect(hosts[1].hostName, 'raspberry.lan');
      expect(hosts[1].user, isNull);
      expect(hosts[1].port, 22);
    });

    test('a pattern is not a machine, and lends its values to the rest', () {
      final hosts = parseSshConfig('''
Host db
  User postgres

Host *.lan !old.lan
  Port 2200

Host nas.lan old.lan

Host *
  User me
  IdentityFile ~/.ssh/id_ed25519
''');

      expect(hosts.map((h) => h.alias), ['db', 'nas.lan', 'old.lan']);
      expect(hosts[0].user, 'postgres');
      expect(hosts[0].identityFile, '~/.ssh/id_ed25519');
      expect(hosts[1].port, 2200);
      expect(hosts[1].user, 'me');
      expect(hosts[2].port, 22);
    });

    test('a host with no HostName is its own address', () {
      expect(parseSshConfig('Host example.com').single.hostName, 'example.com');
    });

    test('Match blocks are stepped over', () {
      final hosts = parseSshConfig('''
Host a
  User one
Match host a
  User two
  Port 9
Host b
''');

      expect(hosts.map((h) => h.alias), ['a', 'b']);
      expect(hosts[0].user, 'one');
      expect(hosts[1].port, 22);
    });
  });

  group('readSshConfigCandidates', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('termphin_ssh_config');
      await Directory('${home.path}/.ssh').create();
    });

    tearDown(() => home.delete(recursive: true));

    Future<void> write(String name, String content) =>
        File('${home.path}/.ssh/$name').writeAsString(content);

    test('no config means nothing to offer', () async {
      expect(await readSshConfigCandidates(home: home.path), isEmpty);
    });

    test('pairs a host with the key it names, or the default one', () async {
      await write('work', 'WORK KEY');
      await write('id_ed25519', 'DEFAULT KEY');
      await write('config', '''
Host web
  User root
  IdentityFile ~/.ssh/work
Host pi
''');

      final found = await readSshConfigCandidates(
        home: home.path,
        localUser: 'me',
      );

      expect(found[0].importable, isTrue);
      expect(found[0].keyPem, 'WORK KEY');
      expect(found[0].username, 'root');
      expect(found[1].importable, isTrue);
      expect(found[1].keyPem, 'DEFAULT KEY');
      expect(found[1].username, 'me');
    });

    test('says why a host cannot come in as it is', () async {
      await write('config', '''
Host nokey
Host gone
  IdentityFile ~/.ssh/missing
Host mine
  User me
  IdentityFile ~/.ssh/key
''');
      await write('key', 'KEY');

      final found = await readSshConfigCandidates(
        home: home.path,
        localUser: 'me',
        existing: {sshConfigIdentity('me', 'mine', 22)},
      );

      expect(found[0].problem, SshConfigProblem.noKey);
      expect(found[1].problem, SshConfigProblem.unreadableKey);
      expect(found[2].problem, SshConfigProblem.alreadyAdded);
    });
  });
}

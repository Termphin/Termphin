import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/services/platform/local_ssh_keys.dart';

const _pem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmU=
-----END OPENSSH PRIVATE KEY-----''';

SshKey _imported({String pem = 'other', String public = 'ssh-ed25519 X c'}) =>
    SshKey(
      id: 'k1',
      name: 'k1',
      keyType: SshKeyType.ed25519,
      privateKeyPem: pem,
      publicKeyOpenSSH: public,
      createdAt: DateTime(2026),
    );

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('local_ssh_keys_test');
    await File('${folder.path}/id_ed25519').writeAsString('$_pem\n');
    await File(
      '${folder.path}/id_ed25519.pub',
    ).writeAsString('ssh-ed25519 AAAABLOB me@laptop\n');
    await File('${folder.path}/known_hosts').writeAsString('host ssh-rsa AAA');
    await File('${folder.path}/config').writeAsString('Host *\n');
    await File('${folder.path}/notes.txt').writeAsString('not a key');
  });

  tearDown(() => folder.delete(recursive: true));

  test('finds the private keys and nothing else in the folder', () async {
    final found = await LocalSshKeys(directory: folder).scan();

    expect(found.map((key) => key.name), ['id_ed25519']);
    expect(found.single.displayPath, '~/.ssh/id_ed25519');
    expect(found.single.pem, _pem.trim());
    expect(found.single.publicKeyBlob, 'AAAABLOB');
    expect(found.single.encrypted, isFalse);
    expect(found.single.algorithm, 'ed25519');
  });

  test('leaves out a key whose private half is already imported', () async {
    final found = await LocalSshKeys(
      directory: folder,
    ).scan(imported: [_imported(pem: _pem.trim())]);

    expect(found, isEmpty);
  });

  test('leaves out a key whose public half is already imported', () async {
    final found = await LocalSshKeys(directory: folder).scan(
      imported: [_imported(public: 'ssh-ed25519 AAAABLOB another-comment')],
    );

    expect(found, isEmpty);
  });

  test('a file too large to be a key is not read as one', () async {
    await File(
      '${folder.path}/huge',
    ).writeAsString('-----BEGIN OPENSSH PRIVATE KEY-----\n${'A' * 70000}');

    final found = await LocalSshKeys(directory: folder).scan();

    expect(found.map((key) => key.name), ['id_ed25519']);
  });

  test('a folder that is not there is no keys, not an error', () async {
    final missing = Directory('${folder.path}/nope');

    expect(await LocalSshKeys(directory: missing).scan(), isEmpty);
  });

  test('the folder is .ssh in the home the system names', () {
    final keys = LocalSshKeys(environment: const {'HOME': '/home/someone'});

    expect(keys.directory?.path, '/home/someone/.ssh');
  });
}

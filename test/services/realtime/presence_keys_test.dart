import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/realtime/presence_keys.dart';

import '../../support/fake_master_key_store.dart';

void main() {
  test('the key round-trips through its written form', () {
    final key = newPresenceKey();
    expect(key, hasLength(32));
    final written = encodePresenceKey(key);
    expect(written, isNot(contains('=')));
    expect(parsePresenceKey(written), key);
  });

  test('the key is found among noise on other lines', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final output = '#< CLIXML\r\n${encodePresenceKey(key)}\r\n<Objs/>\n';
    expect(parsePresenceKey(output), key);
    expect(parsePresenceKey('no key here\n'), isNull);
    expect(parsePresenceKey('AAEC\n'), isNull);
  });

  test(
    'the POSIX command keeps an existing key and the file owner-only',
    () async {
      final home = await Directory.systemTemp.createTemp('presence_home');
      addTearDown(() => home.delete(recursive: true));
      Future<String> run(String key) async {
        final result = await Process.run(
          'sh',
          ['-c', presenceKeyCommand('https://rt.termphin.dev', key)],
          environment: {'HOME': home.path},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return result.stdout as String;
      }

      final first = encodePresenceKey(newPresenceKey());
      final second = encodePresenceKey(newPresenceKey());
      expect((await run(first)).trim(), first);
      expect((await run(second)).trim(), first);
      final file = File('${home.path}/.config/termphin/presence');
      expect(file.readAsStringSync(), 'https://rt.termphin.dev $first\n');
      expect(file.statSync().mode & 0x1ff, 0x180);
    },
    skip: Platform.isWindows,
  );

  test('the Windows command keeps an existing key and restricts the file', () {
    final command = presenceKeyCommandWindows('https://rt.termphin.dev', 'KEY');
    final encoded = RegExp(r'-EncodedCommand (\S+)').firstMatch(command)![1]!;
    final bytes = base64Decode(encoded);
    final script = String.fromCharCodes([
      for (var i = 0; i + 1 < bytes.length; i += 2)
        bytes[i] | bytes[i + 1] << 8,
    ]);
    expect(script, contains(r"Join-Path $dir 'presence'"));
    expect(script, contains(r'if (-not $current -or -not $current.Trim())'));
    expect(script, contains("'https://rt.termphin.dev KEY'"));
    expect(script, contains('icacls'));
    expect(script, contains(r'$fields[1]'));
  });

  test('keys survive a restart, sealed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeMasterKeyStore();
    final key = newPresenceKey();
    final first = PresenceKeyStore(cipher: cipherFixture(store: store));
    await first.remember('profile-1', key);
    expect(first.changes.value, 1);
    await first.remember('profile-1', key);
    expect(first.changes.value, 1);

    final stored = (await SharedPreferences.getInstance()).getString(
      'presence_keys',
    )!;
    expect(stored, isNot(contains(encodePresenceKey(key))));

    final second = PresenceKeyStore(cipher: cipherFixture(store: store));
    expect(await second.keyFor('profile-1'), key);
    expect(await second.keyFor('profile-2'), isNull);
  });

  test('keys travel to the account as records and come back whole', () {
    final key = newPresenceKey();
    expect(presenceKeyFromData(presenceKeyData(key)), key);
    expect(presenceKeyFromData({'key': encodePresenceKey(key)}), key);
    expect(presenceKeyFromData({'key': 'short'}), isNull);
    expect(presenceKeyFromData({'key': '!!not base64!!'}), isNull);
    expect(presenceKeyFromData({'key': 7}), isNull);
    expect(presenceKeyFromData(const {}), isNull);
  });

  test(
    'every key is listed for sync, and a machine deleted elsewhere loses its key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PresenceKeyStore(
        cipher: cipherFixture(store: FakeMasterKeyStore()),
      );
      final one = newPresenceKey();
      final two = newPresenceKey();
      await store.remember('profile-1', one);
      await store.remember('profile-2', two);
      expect(await store.all(), {'profile-1': one, 'profile-2': two});
      final before = store.changes.value;
      await store.forget('profile-1');
      expect(await store.all(), {'profile-2': two});
      expect(store.changes.value, before + 1);
      await store.forget('profile-1');
      expect(store.changes.value, before + 1);
    },
  );

  test(
    'the immediate presence command runs the agent when installed',
    () async {
      final home = await Directory.systemTemp.createTemp(
        'termphin-presence-now',
      );
      addTearDown(() => home.delete(recursive: true));
      final bin = File('${home.path}/.local/lib/termphin/termphin-agent')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\nprintf "%s\\n" "\$@" > "${home.path}/ran"\n',
        );
      await Process.run('chmod', ['+x', bin.path]);
      final result = await Process.run(
        'sh',
        ['-c', presenceReportNowCommand()],
        environment: {'HOME': home.path},
      );
      expect(result.exitCode, 0);
      expect(File('${home.path}/ran').readAsStringSync().trim(), 'presence');
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/push/push_service.dart';

void main() {
  late Directory home;
  late File relay;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('relay_quiet');
    relay = File('${home.path}/.config/termphin/relay');
  });
  tearDown(() => home.delete(recursive: true));

  Future<void> run(String command) async {
    final result = await Process.run(
      'sh',
      ['-c', command],
      environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  test('a quiet key is written with the mark, a loud one without', () async {
    await run(relayInstallCommand('https://relay', 'id.secret', quiet: true));
    expect(relay.readAsStringSync(), 'https://relay id.secret quiet\n');
    await run(relayInstallCommand('https://relay', 'id.secret'));
    expect(relay.readAsStringSync(), 'https://relay id.secret\n');
  });

  test('the mark is set and cleared on the key already there', () async {
    await run(relayInstallCommand('https://relay', 'id.secret'));
    await run(relayQuietCommand(quiet: true));
    expect(relay.readAsStringSync(), 'https://relay id.secret quiet\n');
    await run(relayQuietCommand(quiet: true));
    expect(relay.readAsStringSync(), 'https://relay id.secret quiet\n');
    await run(relayQuietCommand(quiet: false));
    expect(relay.readAsStringSync(), 'https://relay id.secret\n');
    expect(relay.statSync().mode & 0x1ff, 0x180);
  });

  test('without a key there is nothing to mark', () async {
    await run(relayQuietCommand(quiet: true));
    expect(relay.existsSync(), isFalse);
  });

  test('the key id command still reads a quiet file', () async {
    await run(
      relayInstallCommand('https://relay', 'keyid.secret', quiet: true),
    );
    final result = await Process.run(
      'sh',
      ['-c', relayKeyIdCommand],
      environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin'},
    );
    expect((result.stdout as String).trim(), 'keyid');
  });
}

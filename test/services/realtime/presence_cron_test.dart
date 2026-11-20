import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/realtime/presence_keys.dart';

/// Runs [command] with a fake `crontab` on the PATH that keeps its table in
/// [table], answers `-l` like the real one, and fails `-l` with [listError]
/// when set.
Future<void> _run(String command, Directory home, {String? listError}) async {
  final bin = Directory('${home.path}/bin')..createSync(recursive: true);
  final table = File('${home.path}/crontab.txt');
  File('${bin.path}/crontab')
    ..writeAsStringSync('''#!/bin/sh
if [ "\$1" = "-l" ]; then
  ${listError == null ? '' : 'echo "$listError" >&2; exit 1'}
  [ -f "${table.path}" ] || { echo "no crontab for tester" >&2; exit 1; }
  cat "${table.path}"
elif [ "\$1" = "-" ]; then
  cat > "${table.path}"
fi
''')
    ..setLastModifiedSync(DateTime.now());
  await Process.run('chmod', ['+x', '${bin.path}/crontab']);
  final result = await Process.run(
    'sh',
    ['-c', command],
    environment: {'HOME': home.path, 'PATH': '${bin.path}:/usr/bin:/bin'},
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

void main() {
  late Directory home;
  late File table;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('presence_cron');
    table = File('${home.path}/crontab.txt');
  });
  tearDown(() => home.delete(recursive: true));

  List<String> lines() =>
      table.existsSync() ? table.readAsLinesSync() : const [];

  test('adds both lines to an empty crontab, once', () async {
    await _run(presenceCronInstallCommand(), home);
    await _run(presenceCronInstallCommand(), home);
    expect(lines(), hasLength(2));
    expect(
      lines()[0],
      startsWith(
        '*/5 * * * * "${home.path}/.local/lib/termphin/termphin-agent" presence',
      ),
    );
    expect(lines()[1], startsWith('@reboot sleep 60 && '));
    expect(lines().every((line) => line.endsWith(presenceCronTag)), isTrue);
  });

  test('keeps the user\'s own lines in place', () async {
    table.writeAsStringSync('MAILTO=me\n0 3 * * * backup.sh\n');
    await _run(presenceCronInstallCommand(), home);
    expect(lines().take(2), ['MAILTO=me', '0 3 * * * backup.sh']);
    expect(lines(), hasLength(4));

    await _run(presenceCronRemoveCommand(), home);
    expect(lines(), ['MAILTO=me', '0 3 * * * backup.sh']);
  });

  test('writes nothing when the crontab cannot be read', () async {
    table.writeAsStringSync('0 3 * * * backup.sh\n');
    await _run(
      presenceCronInstallCommand(),
      home,
      listError: 'crontab: permission denied',
    );
    expect(lines(), ['0 3 * * * backup.sh']);
  });

  test('removing with nothing of ours there changes nothing', () async {
    table.writeAsStringSync('0 3 * * * backup.sh\n');
    final before = table.lastModifiedSync();
    await _run(presenceCronRemoveCommand(), home);
    expect(lines(), ['0 3 * * * backup.sh']);
    expect(table.lastModifiedSync(), before);
  });
}

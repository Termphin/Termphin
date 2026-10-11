@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

import 'live_env.dart';

/// Guards the socket option the app opens its connections with. dartssh2's own
/// `SSHSocket.connect` leaves Nagle on, which costs about 40ms on every small
/// request - a keystroke echo, an SFTP stat, one file of a delete - so
/// [SshService] connects through [connectInteractiveSocket] instead. Each test
/// measures both and fails if the default drifts back.
final _portEnv = Platform.environment['TERMPHIN_LIVE_SSH_PORT'];
final _live = _portEnv != null;
final _port = int.tryParse(_portEnv ?? '') ?? 0;
const _host = '127.0.0.1';

SshProfile _profile() => SshProfile(
  id: 'live',
  name: 'live',
  host: _host,
  port: _port,
  username: 'tester',
  authMethod: AuthMethod.password,
  password: 'testpass',
  createdAt: DateTime.now(),
);

/// What [SshService] uses today: `SSHSocket.connect`, no socket options.
Future<SSHSocket> _stockConnector(
  String host,
  int port, {
  required Duration timeout,
}) => SSHSocket.connect(host, port, timeout: timeout);

Future<int> _timeSequentialStats(SshService ssh, String dir, int count) async {
  final sftp = SftpService(ssh.client!);
  await sftp.init();
  final started = DateTime.now();
  for (var i = 0; i < count; i++) {
    await sftp.stat('$dir/f$i');
  }
  return DateTime.now().difference(started).inMilliseconds;
}

Future<int> _timeKeystrokeEcho(SshService ssh, int rounds) async {
  final buffer = StringBuffer();
  ssh.output.listen(
    (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
  );
  final session = await ssh.startShell();
  await Future<void>.delayed(const Duration(seconds: 1));
  final started = DateTime.now();
  for (var i = 0; i < rounds; i++) {
    final marker = 'ECHO$i';
    session.write(Uint8List.fromList(utf8.encode('echo $marker\n')));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!buffer.toString().contains('$marker\r\n') &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
  return DateTime.now().difference(started).inMilliseconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live latency', () {
    setUpAll(initLiveEnv);

    test('small sequential SFTP calls, stock socket vs TCP_NODELAY', () async {
      const count = 60;
      final setup = SshService();
      await setup.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      final dir = '/home/tester/lat-${DateTime.now().microsecondsSinceEpoch}';
      await setup.client!.run(
        'mkdir -p $dir && cd $dir && seq 0 ${count - 1} | '
        r'xargs -I{} touch f{}',
      );

      final stock = SshService(socketConnector: _stockConnector);
      await stock.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      final stockMs = await _timeSequentialStats(stock, dir, count);
      await stock.disconnect();

      final fast = SshService();
      await fast.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      final fastMs = await _timeSequentialStats(fast, dir, count);
      await fast.disconnect();

      // ignore: avoid_print
      print(
        '$count sequential stat calls: stock socket ${stockMs}ms '
        '(${(stockMs / count).toStringAsFixed(1)}ms each), '
        'app default ${fastMs}ms '
        '(${(fastMs / count).toStringAsFixed(1)}ms each)',
      );
      expect(
        fastMs * 4,
        lessThan(stockMs),
        reason: 'the default socket is paying the Nagle delay again',
      );

      await setup.client!.run('rm -rf $dir');
      await setup.disconnect();
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('keystroke round trips, stock socket vs TCP_NODELAY', () async {
      const rounds = 25;
      final stock = SshService(socketConnector: _stockConnector);
      await stock.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      final stockMs = await _timeKeystrokeEcho(stock, rounds);
      await stock.disconnect();

      final fast = SshService();
      await fast.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      final fastMs = await _timeKeystrokeEcho(fast, rounds);
      await fast.disconnect();

      // ignore: avoid_print
      print(
        '$rounds command round trips: stock socket ${stockMs}ms '
        '(${(stockMs / rounds).toStringAsFixed(1)}ms each), '
        'app default ${fastMs}ms '
        '(${(fastMs / rounds).toStringAsFixed(1)}ms each)',
      );
      expect(fastMs * 4, lessThan(stockMs));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('deleting many small files, stock socket vs TCP_NODELAY', () async {
      Future<int> run(SocketConnector connector) async {
        final ssh = SshService(socketConnector: connector);
        await ssh.connect(_profile(), onHostKeyPrompt: acceptHostKey);
        final dir = '/home/tester/del-${DateTime.now().microsecondsSinceEpoch}';
        await ssh.client!.run(
          'mkdir -p $dir && cd $dir && seq 1 120 | xargs -I{} touch f{}',
        );
        final sftp = SftpService(ssh.client!);
        await sftp.init();
        final started = DateTime.now();
        await sftp.deletePath(dir, isDirectory: true);
        final ms = DateTime.now().difference(started).inMilliseconds;
        await ssh.disconnect();
        return ms;
      }

      final stockMs = await run(_stockConnector);
      final fastMs = await run(connectInteractiveSocket);
      // ignore: avoid_print
      print(
        'deleting 120 files: stock socket ${stockMs}ms, '
        'app default ${fastMs}ms',
      );
      expect(fastMs * 4, lessThan(stockMs));
    }, timeout: const Timeout(Duration(minutes: 10)));
  }, skip: !_live);
}

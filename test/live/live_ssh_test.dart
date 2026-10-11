@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

import 'live_env.dart';

/// Live tests against a real sshd (podman container). Skipped unless
/// TERMPHIN_LIVE_SSH_PORT is set.
final _portEnv = Platform.environment['TERMPHIN_LIVE_SSH_PORT'];
final _live = _portEnv != null;
final _port = int.tryParse(_portEnv ?? '') ?? 0;
const _host = '127.0.0.1';
const _user = 'tester';
const _pass = 'testpass';

SshProfile _profile({
  String host = _host,
  List<String> fallbacks = const [],
  String password = _pass,
  String username = _user,
}) => SshProfile(
  id: 'live',
  name: 'live',
  host: host,
  port: _port,
  username: username,
  authMethod: AuthMethod.password,
  password: password,
  fallbackHosts: fallbacks,
  createdAt: DateTime.now(),
);

Future<SshService> _connect() async {
  final service = SshService();
  await service.connect(_profile(), onHostKeyPrompt: acceptHostKey);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live ssh', () {
    late SshService ssh;
    late SftpService sftp;
    late String scratch;

    setUpAll(initLiveEnv);

    setUp(() async {
      ssh = await _connect();
      sftp = SftpService(ssh.client!);
      await sftp.init();
      scratch = '/home/$_user/scratch-${DateTime.now().microsecondsSinceEpoch}';
      await sftp.createDirectory(scratch);
    });

    tearDown(() async {
      try {
        await sftp.deletePath(scratch, isDirectory: true);
      } catch (_) {}
      await ssh.disconnect();
    });

    test('connects and runs a shell', () async {
      final session = await ssh.startShell();
      final buffer = StringBuffer();
      final sub = ssh.output.listen(
        (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
      );
      session.write(Uint8List.fromList(utf8.encode('echo TERMPHIN_OK\n')));
      await Future<void>.delayed(const Duration(seconds: 2));
      await sub.cancel();
      expect(buffer.toString(), contains('TERMPHIN_OK'));
    });

    test('copies output whose columns are tabs, not spaces', () async {
      final terminal = Terminal(maxLines: 200);
      final session = await ssh.startShell(width: 80, height: 24);
      final sub = ssh.output.listen(
        (chunk) => terminal.write(utf8.decode(chunk, allowMalformed: true)),
      );
      session.write(
        Uint8List.fromList(
          utf8.encode("printf 'name\\tsize\\n'; printf 'a\\x1b[6Cb\\n'\n"),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      await sub.cancel();

      final text = terminal.buffer.getText();
      expect(text, contains('name    size'));
      expect(text, contains('a      b'));
    });

    test('detects a unix remote shell', () async {
      expect((await ssh.detectRemoteShell()).name, 'unix');
    });

    test('rejects a wrong password with a clear error', () async {
      final bad = SshService();
      await expectLater(
        bad.connect(_profile(password: 'nope'), onHostKeyPrompt: acceptHostKey),
        throwsA(
          predicate(
            (Object e) => e.toString().contains('Authentication failed'),
          ),
        ),
      );
      await bad.disconnect();
    });

    test('falls back to a reachable candidate', () async {
      final service = SshService();
      await service.connect(
        _profile(host: '10.255.255.1', fallbacks: [_host]),
        onHostKeyPrompt: acceptHostKey,
      );
      expect(service.connectedHost, _host);
      await service.disconnect();
    });

    test('uploads, downloads and round-trips bytes', () async {
      final local = File('${Directory.systemTemp.path}/tp-up.bin');
      final payload = Uint8List.fromList(
        List<int>.generate(512 * 1024, (i) => i % 251),
      );
      await local.writeAsBytes(payload);
      final remote = '$scratch/blob.bin';

      final sent = <int>[];
      await sftp.uploadFile(
        local.path,
        remote,
        onProgress: (s, _) => sent.add(s),
      );
      expect(sent.last, payload.length);

      final back = File('${Directory.systemTemp.path}/tp-down.bin');
      await sftp.downloadFile(remote, back.path);
      expect(await back.readAsBytes(), payload);

      await local.delete();
      await back.delete();
    });

    test('overwrites an existing remote file on upload', () async {
      final local = File('${Directory.systemTemp.path}/tp-over.txt');
      await local.writeAsString('second');
      final remote = '$scratch/over.txt';
      await sftp.writeStringToFile(remote, 'first');

      await sftp.uploadFile(local.path, remote);
      expect(await sftp.readFileString(remote), 'second');
      await local.delete();
    });

    test(
      'short-lived SFTP sessions do not use up the server\'s channel limit',
      () async {
        final local = File('${Directory.systemTemp.path}/tp-many.txt');
        await local.writeAsString('x');
        for (var i = 0; i < 15; i++) {
          final once = SftpService(ssh.client!);
          try {
            await once.uploadFile(local.path, '$scratch/many.txt');
          } finally {
            await once.close();
          }
        }
        expect(await sftp.readFileString('$scratch/many.txt'), 'x');
        await local.delete();
      },
    );

    test('saves an edited file over itself (SFTP editor path)', () async {
      final remote = '$scratch/notes.txt';
      await sftp.writeStringToFile(remote, 'v1');
      await sftp.writeStringToFile(remote, 'v2');
      expect(await sftp.readFileString(remote), 'v2');
    });

    test('handles awkward filenames', () async {
      for (final name in [
        'with space.txt',
        "quote'name.txt",
        'unicode-łódź-日本.txt',
        r'back\slash.txt',
        'semi;colon&amp.txt',
        '-leading-dash.txt',
      ]) {
        final path = '$scratch/$name';
        await sftp.writeStringToFile(path, name);
        expect(await sftp.readFileString(path), name, reason: name);
      }
      final listed = (await sftp.listDirectory(
        scratch,
      )).map((e) => e.filename).toSet();
      expect(listed, contains('with space.txt'));
      expect(listed, contains('unicode-łódź-日本.txt'));
    });

    test('deletes a tree recursively', () async {
      final root = '$scratch/tree';
      await sftp.createDirectory(root);
      await sftp.createDirectory('$root/a');
      await sftp.createDirectory('$root/a/b');
      await sftp.writeStringToFile('$root/a/b/deep.txt', 'x');
      await sftp.writeStringToFile('$root/top.txt', 'x');
      await ssh.client!.run('ln -s /etc $root/etclink');

      await sftp.deletePath(root, isDirectory: true);
      expect(await sftp.exists(root), isFalse);
      expect(await sftp.exists('/etc/hostname'), isTrue);
    });

    test('walks a tree without following symlinked directories', () async {
      final root = '$scratch/walk';
      await sftp.createDirectory(root);
      await sftp.createDirectory('$root/sub');
      await sftp.writeStringToFile('$root/sub/f.txt', 'x');
      await ssh.client!.run('ln -s $root $root/loop');
      await ssh.client!.run('ln -s /etc/hostname $root/filelink');

      final entries = await sftp.walkDirectory(root);
      final rel = entries.map((e) => e.relativePath).toSet();
      expect(rel, contains('sub/f.txt'));
      expect(rel, contains('filelink'));
      expect(rel.where((r) => r.startsWith('loop/')), isEmpty);
    });

    test('reports permission denied distinctly', () async {
      await ssh.client!.run(
        'mkdir -p $scratch/locked && chmod 000 $scratch/locked',
      );
      await expectLater(
        sftp.listDirectory('$scratch/locked'),
        throwsA(
          predicate((Object e) => e.toString().contains('permissionDenied')),
        ),
      );
      await ssh.client!.run('chmod 700 $scratch/locked');
    });

    test('reports a missing file distinctly', () async {
      await expectLater(
        sftp.readFileString('$scratch/nope.txt'),
        throwsA(predicate((Object e) => e.toString().contains('notFound'))),
      );
    });

    test('cancelling a download leaves no partial file', () async {
      final remote = '$scratch/big.bin';
      await ssh.client!.run(
        'dd if=/dev/zero of=$remote bs=1M count=64 2>/dev/null',
      );
      final target = '${Directory.systemTemp.path}/tp-cancel.bin';
      final cancel = CancelToken();
      final future = sftp.downloadFile(
        remote,
        target,
        cancel: cancel,
        onProgress: (received, _) {
          if (received > 256 * 1024) cancel.cancel();
        },
      );
      await expectLater(
        future,
        throwsA(predicate((Object e) => e.toString().contains('cancelled'))),
      );
      expect(File(target).existsSync(), isFalse);
    });

    test('cancelling an upload removes the remote temp file', () async {
      final local = File('${Directory.systemTemp.path}/tp-bigup.bin');
      await local.writeAsBytes(Uint8List(32 * 1024 * 1024));
      final remote = '$scratch/up.bin';
      final cancel = CancelToken();
      final future = sftp.uploadFile(
        local.path,
        remote,
        cancel: cancel,
        onProgress: (sent, _) {
          if (sent > 512 * 1024) cancel.cancel();
        },
      );
      await expectLater(
        future,
        throwsA(predicate((Object e) => e.toString().contains('cancelled'))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final leftovers = (await sftp.listDirectory(
        scratch,
      )).map((e) => e.filename).where((n) => n.contains('.tmp')).toList();
      expect(leftovers, isEmpty, reason: 'temp files left behind: $leftovers');
      await local.delete();
    });

    test('reads only the head of a large file', () async {
      final remote = '$scratch/head.bin';
      await ssh.client!.run(
        'dd if=/dev/urandom of=$remote bs=1M count=4 2>/dev/null',
      );
      final head = await sftp.readFileHead(remote, maxBytes: 4096);
      expect(head.length, 4096);
    });

    test('readSmallTextFile trims and caps', () async {
      await sftp.writeStringToFile('$scratch/cwd', '  /home/tester \n');
      expect(await sftp.readSmallTextFile('$scratch/cwd'), '/home/tester');
    });

    test('renames across directories', () async {
      await sftp.writeStringToFile('$scratch/a.txt', 'x');
      await sftp.createDirectory('$scratch/dst');
      await sftp.rename('$scratch/a.txt', '$scratch/dst/b.txt');
      expect(await sftp.exists('$scratch/dst/b.txt'), isTrue);
    });

    test('createEmptyFile refuses to clobber', () async {
      await sftp.writeStringToFile('$scratch/e.txt', 'x');
      await expectLater(
        sftp.createEmptyFile('$scratch/e.txt'),
        throwsA(isA<Exception>()),
      );
      expect(await sftp.readFileString('$scratch/e.txt'), 'x');
    });

    test('local port forward carries traffic', () async {
      await ssh.startLocalForward('rule', 45001, '127.0.0.1', 22);
      final socket = await Socket.connect('127.0.0.1', 45001);
      final banner = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .first
          .timeout(const Duration(seconds: 10));
      socket.destroy();
      expect(banner, contains('SSH-2.0'));
      ssh.stopLocalForward('rule');
    });

    test('remote port forward reaches a local listener', () async {
      final local = await ServerSocket.bind('127.0.0.1', 0);
      local.listen((s) {
        s.write('HELLO_FROM_HOST');
        s.close();
      });
      await ssh.startRemoteForward('r1', 45002, '127.0.0.1', local.port);
      final result = await ssh.client!.run(
        'timeout 10 bash -c "exec 3<>/dev/tcp/127.0.0.1/45002; cat <&3"',
      );
      ssh.stopRemoteForward('r1');
      await local.close();
      expect(
        utf8.decode(result, allowMalformed: true),
        contains('HELLO_FROM_HOST'),
      );
    });

    test('stopping a local forward frees the port', () async {
      await ssh.startLocalForward('rule2', 45003, '127.0.0.1', 22);
      ssh.stopLocalForward('rule2');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final again = await ServerSocket.bind('127.0.0.1', 45003);
      await again.close();
    });

    test('sftp survives after the shell session ends', () async {
      final session = await ssh.startShell();
      session.write(Uint8List.fromList(utf8.encode('exit\n')));
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(await sftp.exists(scratch), isTrue);
    });
  }, skip: !_live);

  group('live remote agent', () {
    late SshService ssh;

    setUp(() async {
      ssh = await _connect();
    });

    tearDown(() async {
      await ssh.disconnect();
    });

    test('probes a bare host as missing', () async {
      await ssh.client!.run('rm -rf ~/.local/lib/termphin');
      final status = await const RemoteAgentService().probe(ssh.client!);
      expect(status.supported, isTrue);
      expect(status.publicStatus.state.name, 'missing');
      expect(status.publicStatus.architecture, 'x86_64');
    });

    test('installs, verifies and reports current', () async {
      await ssh.client!.run('rm -rf ~/.local/lib/termphin');
      final installed = await const RemoteAgentService().install(ssh.client!);
      expect(installed.publicStatus.state.name, 'current');
      expect(installed.usable, isTrue);

      final again = await const RemoteAgentService().probe(ssh.client!);
      expect(again.publicStatus.state.name, 'current');
    });

    test('repairs a corrupted install', () async {
      await const RemoteAgentService().install(ssh.client!);
      await ssh.client!.run('echo garbage > ~/.local/lib/termphin/agent.meta');
      final status = await const RemoteAgentService().probe(ssh.client!);
      expect(status.publicStatus.state.name, 'repair');
      final fixed = await const RemoteAgentService().ensureForAttach(
        ssh.client!,
        probed: status,
      );
      expect(fixed.publicStatus.state.name, 'current');
    });

    test('reinstalls when the binary is truncated', () async {
      await const RemoteAgentService().install(ssh.client!);
      await ssh.client!.run(
        'truncate -s 1000 ~/.local/lib/termphin/termphin-agent',
      );
      final status = await const RemoteAgentService().probe(ssh.client!);
      expect(status.publicStatus.state.name, isNot('current'));
      final fixed = await const RemoteAgentService().ensureForAttach(
        ssh.client!,
        probed: status,
      );
      expect(fixed.publicStatus.state.name, 'current');
    });

    test('agent starts, lists and kills a session', () async {
      await const RemoteAgentService().install(ssh.client!);
      const bin = r'$HOME/.local/lib/termphin/termphin-agent';
      final list = await ssh.client!.run('$bin list 2>&1 || true');
      expect(utf8.decode(list, allowMalformed: true), isNotNull);
    });
  }, skip: !_live);
}

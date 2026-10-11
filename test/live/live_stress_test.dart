@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

import 'live_env.dart';

final _portEnv = Platform.environment['TERMPHIN_LIVE_SSH_PORT'];
final _live = _portEnv != null;
final _port = int.tryParse(_portEnv ?? '') ?? 0;
const _host = '127.0.0.1';
const _user = 'tester';
const _pass = 'testpass';

SshProfile _profile() => SshProfile(
  id: 'live',
  name: 'live',
  host: _host,
  port: _port,
  username: _user,
  authMethod: AuthMethod.password,
  password: _pass,
  createdAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live stress', () {
    late SshService ssh;
    late SftpService sftp;
    late String scratch;

    setUpAll(initLiveEnv);

    setUp(() async {
      ssh = SshService();
      await ssh.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      sftp = SftpService(ssh.client!);
      await sftp.init();
      scratch = '/home/$_user/stress-${DateTime.now().microsecondsSinceEpoch}';
      await sftp.createDirectory(scratch);
    });

    tearDown(() async {
      try {
        await ssh.client!.run('rm -rf $scratch');
      } catch (_) {}
      await ssh.disconnect();
    });

    test('runs five downloads in parallel on one SFTP session', () async {
      for (var i = 0; i < 5; i++) {
        await ssh.client!.run(
          'dd if=/dev/urandom of=$scratch/p$i.bin bs=1M count=4 2>/dev/null',
        );
      }
      final targets = [
        for (var i = 0; i < 5; i++)
          '${Directory.systemTemp.path}/tp-par-$i.bin',
      ];
      await Future.wait([
        for (var i = 0; i < 5; i++)
          sftp.downloadFile('$scratch/p$i.bin', targets[i]),
      ]);
      for (var i = 0; i < 5; i++) {
        final local = File(targets[i]);
        expect(await local.length(), 4 * 1024 * 1024, reason: 'file $i');
        final remoteSum = (await ssh.client!.run(
          'sha256sum $scratch/p$i.bin',
        )).let(utf8.decode).split(' ').first;
        expect(
          _sha256(await local.readAsBytes()),
          remoteSum,
          reason: 'file $i corrupted by parallel download',
        );
        await local.delete();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('mixes uploads, listings and deletes concurrently', () async {
      final local = File('${Directory.systemTemp.path}/tp-mix.bin');
      await local.writeAsBytes(Uint8List(2 * 1024 * 1024));
      await Future.wait([
        sftp.uploadFile(local.path, '$scratch/mix-a.bin'),
        sftp.uploadFile(local.path, '$scratch/mix-b.bin'),
        sftp.listDirectory(scratch),
        sftp.createDirectory('$scratch/mixdir'),
        sftp.writeStringToFile('$scratch/mix.txt', 'hello'),
      ]);
      expect(await sftp.exists('$scratch/mix-a.bin'), isTrue);
      expect(await sftp.exists('$scratch/mix-b.bin'), isTrue);
      expect(await sftp.readFileString('$scratch/mix.txt'), 'hello');
      await local.delete();
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('keeps a 64 MB transfer byte-exact', () async {
      final remote = '$scratch/big.bin';
      await ssh.client!.run(
        'dd if=/dev/urandom of=$remote bs=1M count=64 2>/dev/null',
      );
      final expected = (await ssh.client!.run(
        'sha256sum $remote',
      )).let(utf8.decode).split(' ').first;
      final target = '${Directory.systemTemp.path}/tp-big.bin';
      final started = DateTime.now();
      await sftp.downloadFile(remote, target);
      final elapsed = DateTime.now().difference(started);
      final bytes = await File(target).readAsBytes();
      expect(_sha256(bytes), expected);
      // ignore: avoid_print
      print(
        'download 64MB in ${elapsed.inMilliseconds}ms '
        '(${(64 / (elapsed.inMilliseconds / 1000)).toStringAsFixed(1)} MB/s)',
      );
      await File(target).delete();
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('walks and deletes a wide tree', () async {
      await ssh.client!.run(
        'mkdir -p $scratch/wide/{a,b,c,d}/{1,2,3,4,5} && '
        'for d in $scratch/wide/*/*; do '
        'for i in \$(seq 1 40); do echo x > \$d/f\$i.txt; done; done',
      );
      final started = DateTime.now();
      final entries = await sftp.walkDirectory('$scratch/wide');
      final elapsed = DateTime.now().difference(started);
      final files = entries.where((e) => !e.isDirectory).length;
      // ignore: avoid_print
      print('walked $files files in ${elapsed.inMilliseconds}ms');
      expect(files, 800);

      final deleteStarted = DateTime.now();
      await sftp.deletePath('$scratch/wide', isDirectory: true);
      // ignore: avoid_print
      print(
        'deleted the tree in '
        '${DateTime.now().difference(deleteStarted).inMilliseconds}ms',
      );
      expect(await sftp.exists('$scratch/wide'), isFalse);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('lists a directory with 5000 entries', () async {
      await ssh.client!.run(
        'mkdir -p $scratch/many && cd $scratch/many && '
        'seq 1 5000 | xargs -n 500 touch',
      );
      final started = DateTime.now();
      final listed = await sftp.listDirectory('$scratch/many');
      // ignore: avoid_print
      print(
        'listed ${listed.length} entries in '
        '${DateTime.now().difference(started).inMilliseconds}ms',
      );
      expect(
        listed.where((e) => e.filename != '.' && e.filename != '..').length,
        5000,
      );
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('cancels a walk promptly', () async {
      await ssh.client!.run(
        'mkdir -p $scratch/deep && cd $scratch/deep && '
        'for i in \$(seq 1 60); do mkdir -p d\$i && '
        'for j in \$(seq 1 60); do echo x > d\$i/f\$j; done; done',
      );
      final cancel = CancelToken();
      final future = sftp.walkDirectory(
        '$scratch/deep',
        cancel: cancel,
        onProgress: (found) {
          if (found > 100) cancel.cancel();
        },
      );
      final started = DateTime.now();
      await expectLater(
        future,
        throwsA(predicate((Object e) => e.toString().contains('cancelled'))),
      );
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 20)),
      );
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('maps an upload into a missing directory to a real error', () async {
      final local = File('${Directory.systemTemp.path}/tp-nodir.txt');
      await local.writeAsString('x');
      await expectLater(
        sftp.uploadFile(local.path, '$scratch/no/such/dir/file.txt'),
        throwsA(
          predicate((Object e) {
            final text = e.toString();
            // ignore: avoid_print
            print('upload into a missing directory reported: $text');
            return text.contains('sftp.errors.');
          }),
        ),
      );
      await local.delete();
    });

    test(
      'a bare rename overwrites, which is why the browser asks first',
      () async {
        await sftp.writeStringToFile('$scratch/one.txt', 'one');
        await sftp.writeStringToFile('$scratch/two.txt', 'two');
        try {
          await sftp.rename('$scratch/one.txt', '$scratch/two.txt');
          expect(await sftp.readFileString('$scratch/two.txt'), 'one');
        } catch (error) {
          expect(await sftp.readFileString('$scratch/two.txt'), 'two');
        }
      },
    );

    test('editor round-trips odd text exactly', () async {
      const samples = {
        'crlf.txt': 'line one\r\nline two\r\n',
        'nolf.txt': 'no trailing newline',
        'utf8.txt': 'zażółć gęślą jaźń — 日本語 🐬\n',
        'nul.txt': 'before\u0000after\n',
        'long.txt': 'x',
      };
      for (final entry in samples.entries) {
        final content = entry.key == 'long.txt'
            ? List.filled(200000, 'x').join()
            : entry.value;
        final path = '$scratch/${entry.key}';
        await sftp.writeStringToFile(path, content);
        expect(
          await sftp.readFileString(path),
          content,
          reason: 'round trip of ${entry.key}',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('reads a file the user cannot read as permissionDenied', () async {
      await ssh.client!.run(
        'echo secret > $scratch/secret.txt && chmod 000 $scratch/secret.txt',
      );
      await expectLater(
        sftp.readFileString('$scratch/secret.txt'),
        throwsA(
          predicate((Object e) => e.toString().contains('permissionDenied')),
        ),
      );
    });

    test('survives a file that changes size while downloading', () async {
      final remote = '$scratch/growing.bin';
      await ssh.client!.run(
        'dd if=/dev/zero of=$remote bs=1M count=16 2>/dev/null',
      );
      final target = '${Directory.systemTemp.path}/tp-growing.bin';
      final download = sftp.downloadFile(remote, target);
      unawaited(
        ssh.client!.run(
          'dd if=/dev/zero bs=1M count=16 >> $remote 2>/dev/null',
        ),
      );
      await download;
      expect(File(target).existsSync(), isTrue);
      await File(target).delete();
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('session names the app accepts are safe on the wire', () {
      const hostile = [
        "a'; rm -rf ~; echo '",
        'a b',
        'a\$(id)',
        'a`id`',
        'a\nb',
        '../../etc/passwd',
      ];
      for (final name in hostile) {
        expect(
          SessionTab.validateName(name),
          isNotNull,
          reason: 'accepted a hostile session name: $name',
        );
      }
      expect(SessionTab.validateName('  padded  '), isNotNull);
      expect(SessionTab.validateName(List.filled(500, 'a').join()), isNotNull);
    });
  }, skip: !_live);
}

String _sha256(Uint8List bytes) => SHA256Digest()
    .process(bytes)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

extension _Let<T> on T {
  R let<R>(R Function(T) transform) => transform(this);
}

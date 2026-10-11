@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/sftp/cancel_token.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/utils/editor_limits.dart';
import 'package:termphin/utils/text_sniffer.dart';

import 'live_env.dart';

/// What the SFTP layer does when pointed at something it was never sized for:
/// a huge file, a device node, a growing log.
final _portEnv = Platform.environment['TERMPHIN_LIVE_SSH_PORT'];
final _live = _portEnv != null;
final _port = int.tryParse(_portEnv ?? '') ?? 0;

SshProfile _profile() => SshProfile(
  id: 'live',
  name: 'live',
  host: '127.0.0.1',
  port: _port,
  username: 'tester',
  authMethod: AuthMethod.password,
  password: 'testpass',
  createdAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live limits', () {
    late SshService ssh;
    late SftpService sftp;
    late String scratch;

    setUpAll(initLiveEnv);

    setUp(() async {
      ssh = SshService();
      await ssh.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      sftp = SftpService(ssh.client!);
      await sftp.init();
      scratch = '/home/tester/limits-${DateTime.now().microsecondsSinceEpoch}';
      await sftp.createDirectory(scratch);
    });

    tearDown(() async {
      try {
        await ssh.client!.run('rm -rf $scratch');
      } catch (_) {}
      await ssh.disconnect();
    });

    test('a huge text file is refused by the editor, not loaded', () async {
      final remote = '$scratch/huge.log';
      await ssh.client!.run(
        'yes "2026-08-15 some log line that is reasonably long" | '
        'head -c 201326592 > $remote',
      );
      final head = await sftp.readFileHead(remote, maxBytes: 8 * 1024);
      final probe = probeTextContent(head, truncated: true);
      expect(probe.isText, isTrue);

      final size = (await sftp.stat(remote)).size;
      expect(size, 201326592);
      expect(
        isTooLargeToEdit(size),
        isTrue,
        reason: 'the editor would pull 192MB into a phone-sized heap',
      );
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('a device node never finishes reading', () async {
      final read = sftp.readFileHead('/dev/zero', maxBytes: 8 * 1024);
      final head = await read.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail('readFileHead on /dev/zero never returned'),
      );
      expect(head.length, 8 * 1024);

      final all = await sftp
          .readFileBytes('/dev/zero')
          .timeout(const Duration(seconds: 60));
      // ignore: avoid_print
      print('readFileBytes(/dev/zero) returned ${all.length} bytes');
      expect(all.length, lessThanOrEqualTo(8 * 1024 * 1024));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(
      'stat of a zero-sized proc file still downloads its contents',
      () async {
        final target = '${Directory.systemTemp.path}/tp-proc.txt';
        await sftp.downloadFile('/proc/self/status', target);
        final text = await File(target).readAsString();
        // ignore: avoid_print
        print('downloaded /proc/self/status: ${text.length} bytes');
        expect(text, contains('Name:'));
        await File(target).delete();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'walking a directory that disappears mid-walk fails cleanly',
      () async {
        await ssh.client!.run(
          'mkdir -p $scratch/vanish/{a,b,c} && '
          'for d in $scratch/vanish/*; do seq 1 200 | '
          r'xargs -I{} touch $d/f{}; done',
        );
        final walk = sftp.walkDirectory('$scratch/vanish');
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 150),
          ).then((_) => ssh.client!.run('rm -rf $scratch/vanish/b')),
        );
        try {
          final entries = await walk;
          // ignore: avoid_print
          print('walk survived the deletion: ${entries.length} entries');
        } catch (error) {
          // ignore: avoid_print
          print('walk of a vanishing directory reported: $error');
          expect(error.toString(), contains('sftp.errors.'));
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test('exists() does not claim a path it may not stat is free', () async {
      await ssh.client!.run(
        'mkdir -p $scratch/priv && echo x > $scratch/priv/hidden.txt && '
        'chmod 000 $scratch/priv',
      );
      expect(await sftp.exists('$scratch/priv/hidden.txt'), isTrue);
      expect(await sftp.exists('$scratch/definitely-not-here'), isFalse);
      await ssh.client!.run('chmod 700 $scratch/priv');
    });

    test('a local write that runs out of space is reported', () async {
      final remote = '$scratch/x.bin';
      await ssh.client!.run(
        'dd if=/dev/zero of=$remote bs=1M count=8 2>/dev/null',
      );
      var outcome = 'no result within 30s (hung)';
      try {
        await sftp
            .downloadFile(remote, '/dev/full')
            .timeout(const Duration(seconds: 30));
        outcome = 'returned SUCCESS despite ENOSPC on every write';
      } on TimeoutException {
        outcome = 'hung for 30s';
      } catch (error) {
        outcome = 'reported: $error';
      }
      // ignore: avoid_print
      print('download onto a full disk $outcome');
      expect(outcome, contains('sftp.errors.diskFull'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a local write to an unwritable path is reported', () async {
      final remote = '$scratch/y.bin';
      await ssh.client!.run(
        'dd if=/dev/zero of=$remote bs=1M count=2 2>/dev/null',
      );
      var outcome = 'no result';
      try {
        await sftp
            .downloadFile(remote, '/proc/nope/file.bin')
            .timeout(const Duration(seconds: 30));
        outcome = 'returned SUCCESS';
      } on TimeoutException {
        outcome = 'hung for 30s';
      } catch (error) {
        outcome = 'reported: $error';
      }
      // ignore: avoid_print
      print('download into an unwritable path $outcome');
      expect(outcome, contains('sftp.errors.localWriteError'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('cancel rescues a transfer stuck on a failing local write', () async {
      final remote = '$scratch/z.bin';
      await ssh.client!.run(
        'dd if=/dev/zero of=$remote bs=1M count=8 2>/dev/null',
      );
      final cancel = CancelToken();
      Timer(const Duration(seconds: 3), cancel.cancel);
      var outcome = '';
      try {
        await sftp
            .downloadFile(remote, '/dev/full', cancel: cancel)
            .timeout(const Duration(seconds: 30));
        outcome = 'returned success';
      } on TimeoutException {
        outcome = 'still hung 30s after Cancel';
      } catch (error) {
        outcome = 'reported: $error';
      }
      // ignore: avoid_print
      print('cancelling a download onto a full disk: $outcome');
      expect(
        outcome.contains('cancelled') || outcome.contains('sftp.errors.'),
        isTrue,
        reason: outcome,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: !_live);
}

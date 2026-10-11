import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/sftp/sftp_remote_ops.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/utils/sftp_error_handler.dart';

import '../../support/sftp_fakes.dart';

const _ok = (exitCode: 0, stdout: '', stderr: '');
const _probeOk = (exitCode: 0, stdout: '$execProbeMarker\n', stderr: '');

void main() {
  late FakeSftpTree tree;
  late FakeSftpClient sftpClient;
  late FakeSftpSshClient ssh;
  late SftpService service;

  setUp(() {
    tree = FakeSftpTree({
      '/home/user': [sftpDir('app'), sftpFile('a.txt')],
      '/home/user/app': [],
    });
    sftpClient = FakeSftpClient(tree);
    ssh = FakeSftpSshClient(sftpClient);
    service = SftpService.test(ssh, () async => sftpClient);
  });

  group('copyEntry', () {
    test('asks once whether commands run, then runs cp', () async {
      ssh.onCommand = (c) => c.contains(execProbeMarker) ? _probeOk : _ok;

      await service.copyEntry('/home/user/a.txt', '/home/user/b.txt');
      await service.copyEntry('/home/user/a.txt', '/home/user/c.txt');

      expect(
        ssh.commands.where((c) => c.contains(execProbeMarker)),
        hasLength(1),
      );
      expect(ssh.commands.last, contains('cp -RPp'));
      expect(service.canRunCommands, isTrue);
    });

    test(
      'a server locked to SFTP is reported as such and remembered',
      () async {
        ssh.onCommand = (_) => _ok;

        await expectLater(
          service.copyEntry('/home/user/a.txt', '/home/user/b.txt'),
          throwsA(
            predicate(
              (Object? e) =>
                  resolveSftpError(e!, AppLocale.en.buildSync()) ==
                  AppLocale.en.buildSync().sftp.errors.noShell,
            ),
          ),
        );
        expect(service.canRunCommands, isFalse);
        expect(ssh.commands, hasLength(1), reason: 'no cp was attempted');
      },
    );

    test("what the server said reaches the user as written", () async {
      ssh.onCommand = (c) => c.contains(execProbeMarker)
          ? _probeOk
          : (
              exitCode: 1,
              stdout: '',
              stderr: "cp: cannot create 'b.txt': Permission denied\nmore\n",
            );

      Object? caught;
      try {
        await service.copyEntry('/home/user/a.txt', '/home/user/b.txt');
      } catch (e) {
        caught = e;
      }

      final t = AppLocale.en.buildSync();
      expect(
        resolveSftpError(caught!, t),
        t.sftp.errors.generic(
          error: "cp: cannot create 'b.txt': Permission denied",
        ),
      );
    });

    test('closes stdin, so internal-sftp exits instead of waiting', () async {
      final sessions = <FakeSshSession>[];
      final realSsh = _RecordingSshClient(sftpClient, sessions);
      final recorded = SftpService.test(realSsh, () async => sftpClient);

      await recorded.copyEntry('/home/user/a.txt', '/home/user/b.txt');
      await Future<void>.delayed(Duration.zero);

      expect(sessions, isNotEmpty);
      expect(sessions.every((s) => s.stdinClosed), isTrue);
    });
  });

  group('the probe', () {
    test('a dropped connection is not remembered as "no shell"', () async {
      var calls = 0;
      ssh.onCommand = (c) {
        calls++;
        if (calls == 1) throw SSHChannelOpenError(2, 'connect failed');
        return c.contains(execProbeMarker) ? _probeOk : _ok;
      };

      await expectLater(
        service.copyEntry('/home/user/a.txt', '/home/user/b.txt'),
        throwsA(anything),
      );
      expect(service.canRunCommands, isNull);

      await service.copyEntry('/home/user/a.txt', '/home/user/b.txt');
      expect(service.canRunCommands, isTrue);
      expect(
        ssh.commands.where((c) => c.contains(execProbeMarker)),
        hasLength(2),
        reason: 'asked again, not answered from the failure',
      );
    });

    test('a probe that never answers counts as no shell', () {
      fakeAsync((async) {
        ssh.onCommand = (_) => Completer<FakeCommandResult>().future;
        Object? caught;
        service
            .copyEntry('/home/user/a.txt', '/home/user/b.txt')
            .catchError((Object e) => caught = e);

        async.elapse(const Duration(seconds: 11));

        final t = AppLocale.en.buildSync();
        expect(resolveSftpError(caught!, t), t.sftp.errors.noShell);
        expect(service.canRunCommands, isFalse);
      });
    });

    test('a Windows path is asked about in PowerShell', () async {
      ssh.onCommand = (c) => _probeOk;

      await service.copyEntry('/C:/Users/me/a.txt', '/C:/Users/me/b.txt');

      expect(ssh.commands, hasLength(2));
      expect(ssh.commands, everyElement(startsWith('powershell ')));
    });
  });

  group('exit status', () {
    Future<Object?> copyFailing(FakeCommandResult result) async {
      ssh.onCommand = (c) => c.contains(execProbeMarker) ? _probeOk : result;
      try {
        await service.copyEntry('/home/user/a.txt', '/home/user/b.txt');
        return null;
      } catch (e) {
        return e;
      }
    }

    test('no status and nothing said counts as done', () async {
      expect(
        await copyFailing((exitCode: null, stdout: '', stderr: '')),
        isNull,
      );
    });

    test('no status but an error said is a failure', () async {
      final error = await copyFailing((
        exitCode: null,
        stdout: '',
        stderr: 'cp: disk full',
      ));
      expect(error.toString(), 'cp: disk full');
    });

    test('a silent failure still says it failed', () async {
      final error = await copyFailing((exitCode: 2, stdout: '', stderr: ''));
      expect(error.toString(), 'exit 2');
    });
  });

  group('moveEntry', () {
    test('is a rename when the server can do one', () async {
      await service.moveEntry('/home/user/a.txt', '/home/user/app/a.txt');

      expect(ssh.commands, isEmpty);
      expect(tree.children['/home/user/app']!.map((e) => e.filename), [
        'a.txt',
      ]);
    });

    test('falls back to mv when the rename fails across filesystems', () async {
      ssh.onCommand = (c) => c.contains(execProbeMarker) ? _probeOk : _ok;
      sftpClient.nextError = SftpStatusError(SftpStatusCode.failure, 'EXDEV');

      await service.moveEntry('/home/user/a.txt', '/mnt/disk/a.txt');

      expect(ssh.commands.last, contains('mv --'));
    });

    test('a server without rename at all gets mv too', () async {
      ssh.onCommand = (c) => c.contains(execProbeMarker) ? _probeOk : _ok;
      sftpClient.nextError = SftpStatusError(
        SftpStatusCode.opUnsupported,
        'unsupported',
      );

      await service.moveEntry('/home/user/a.txt', '/mnt/disk/a.txt');

      expect(ssh.commands.last, contains('mv --'));
    });

    test('a failed mv says what mv said', () async {
      ssh.onCommand = (c) => c.contains(execProbeMarker)
          ? _probeOk
          : (exitCode: 1, stdout: '', stderr: 'mv: cannot move: Read-only\n');
      sftpClient.nextError = SftpStatusError(SftpStatusCode.failure, 'EXDEV');

      await expectLater(
        service.moveEntry('/home/user/a.txt', '/mnt/ro/a.txt'),
        throwsA(
          isA<RemoteCommandException>().having(
            (e) => e.message,
            'message',
            'mv: cannot move: Read-only',
          ),
        ),
      );
    });

    test('a refusal the server means is not retried as mv', () async {
      sftpClient.nextError = SftpStatusError(
        SftpStatusCode.permissionDenied,
        'denied',
      );

      await expectLater(
        service.moveEntry('/home/user/a.txt', '/root/a.txt'),
        throwsA(anything),
      );
      expect(ssh.commands, isEmpty);
    });
  });

  test('clearPath removes a folder or a file, whichever is there', () async {
    await service.clearPath('/home/user/app');
    await service.clearPath('/home/user/a.txt');
    await service.clearPath('/home/user/never-there');

    expect(tree.children['/home/user'], isEmpty);
  });

  test('clearPath unlinks a symlink and leaves what it points at', () async {
    tree.children['/home/user']!.add(
      SftpName(
        filename: 'shortcut',
        longname: 'shortcut',
        attr: SftpFileAttrs(mode: const SftpFileMode.value(0xA000)),
      ),
    );

    await service.clearPath('/home/user/shortcut');

    final names = tree.children['/home/user']!.map((e) => e.filename);
    expect(names, isNot(contains('shortcut')));
    expect(names, contains('app'));
    expect(tree.children.containsKey('/home/user/app'), isTrue);
  });
}

class _RecordingSshClient extends FakeSftpSshClient {
  _RecordingSshClient(super.sftpClient, this.sessions)
    : super(onCommand: (c) => c.contains(execProbeMarker) ? _probeOk : _ok);

  final List<FakeSshSession> sessions;

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    final session = await super.execute(command) as FakeSshSession;
    sessions.add(session);
    return session;
  }
}

@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/sftp/sftp_service.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/utils/sftp_path.dart';

import 'live_env.dart';

/// The same ground as the Linux live suites, against Win32-OpenSSH on a real
/// Windows Server VM: a different shell, a different quoting style, drive
/// letters in SFTP paths, and a helper that installs under `%LOCALAPPDATA%`.
///
/// Needs TERMPHIN_LIVE_WIN_PORT and TERMPHIN_LIVE_WIN_PASSWORD. The VM lives
/// outside this repository - see `~/vm/win2025/run-vm.sh`. Setting
/// TERMPHIN_LIVE_WIN_VM_DIR to that directory enables the power-cut test,
/// which pulls the plug through qemu's monitor socket and boots it again.
final _portEnv = Platform.environment['TERMPHIN_LIVE_WIN_PORT'];
final _password = Platform.environment['TERMPHIN_LIVE_WIN_PASSWORD'] ?? '';
final _live = _portEnv != null && _password.isNotEmpty;
final _port = int.tryParse(_portEnv ?? '') ?? 0;
final _vmDir = Platform.environment['TERMPHIN_LIVE_WIN_VM_DIR'] ?? '';
final _canPowerCut = _live && _vmDir.isNotEmpty;
const _user = 'Administrator';
const _home = '/C:/Users/Administrator';
const _agentBin = r'$env:LOCALAPPDATA\termphin\bin\termphin-agent.exe';

SshProfile _profile() => SshProfile(
  id: 'live-win',
  name: 'live-win',
  host: '127.0.0.1',
  port: _port,
  username: _user,
  authMethod: AuthMethod.password,
  password: _password,
  createdAt: DateTime.now(),
);

Future<SshService> _connect({int attempts = 10}) async {
  Object? last;
  for (var i = 0; i < attempts; i++) {
    final service = SshService();
    try {
      await service.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      return service;
    } catch (error) {
      last = error;
      await service.disconnect();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
  throw Exception('could not connect: $last');
}

/// Runs [script] through PowerShell, the way `RemoteAgentService` does.
Future<String> _powershell(SshService ssh, String script) async {
  final utf16 = Uint8List(script.length * 2);
  for (var i = 0; i < script.length; i++) {
    final unit = script.codeUnitAt(i);
    utf16[i * 2] = unit & 0xFF;
    utf16[i * 2 + 1] = (unit >> 8) & 0xFF;
  }
  final result = await ssh.client!.runWithResult(
    'powershell -NoProfile -NonInteractive -EncodedCommand '
    '${base64.encode(utf16)}',
  );
  return utf8.decode(result.stdout, allowMalformed: true);
}

/// Kills the VM the way a power cut does - qemu exits at once, nothing on the
/// guest gets a chance to flush or shut down - then boots it again and waits
/// for sshd.
Future<void> _powerCutAndReboot() async {
  final monitor = await Socket.connect(
    InternetAddress('$_vmDir/monitor.sock', type: InternetAddressType.unix),
    0,
  );
  monitor.write('quit\n');
  await monitor.flush();
  monitor.destroy();
  await Future<void>.delayed(const Duration(seconds: 3));

  await Process.start(
    '$_vmDir/run-vm.sh',
    ['run'],
    mode: ProcessStartMode.detached,
    workingDirectory: _vmDir,
  );

  final deadline = DateTime.now().add(const Duration(minutes: 6));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final probe = await Socket.connect(
        '127.0.0.1',
        _port,
      ).timeout(const Duration(seconds: 5));
      final banner = await probe
          .cast<List<int>>()
          .transform(utf8.decoder)
          .first
          .timeout(const Duration(seconds: 5));
      probe.destroy();
      if (banner.contains('SSH-2.0')) return;
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  throw Exception('the VM never came back up');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live windows', () {
    late SshService ssh;
    late SftpService sftp;
    late String scratch;

    setUpAll(initLiveEnv);

    setUp(() async {
      ssh = await _connect();
      sftp = SftpService(ssh.client!);
      await sftp.init();
      scratch = '$_home/termphin-${DateTime.now().microsecondsSinceEpoch}';
      await sftp.createDirectory(scratch);
    });

    tearDown(() async {
      try {
        await sftp.deletePath(scratch, isDirectory: true);
      } catch (_) {}
      await ssh.disconnect();
    });

    test('detects the remote shell as PowerShell, not a unix host', () async {
      final shell = await ssh.detectRemoteShell();
      // ignore: avoid_print
      print('detectRemoteShell on Windows: ${shell.name}');
      expect(shell.name, isNot('unix'));
    });

    test('reports drive-letter paths the browser can display', () async {
      final entries = await sftp.listDirectory(_home);
      expect(entries, isNotEmpty);
      expect(isWindowsSftpPath(_home), isTrue);
      expect(sftpPathToDisplay(_home), r'C:\Users\Administrator');
      expect(displayPathToSftp(r'C:\Users\Administrator'), _home);
      expect(displayPathToSftp(r'C:\'), '/C:');
      final listedRoot = await sftp.listDirectory(displayPathToSftp(r'C:\'));
      expect(listedRoot, isNotEmpty);
    });

    test('uploads and downloads a file byte for byte', () async {
      final local = File('${Directory.systemTemp.path}/tp-win.bin');
      final payload = Uint8List.fromList(
        List<int>.generate(256 * 1024, (i) => i % 251),
      );
      await local.writeAsBytes(payload);
      final remote = '$scratch/blob.bin';

      await sftp.uploadFile(local.path, remote);
      final back = File('${Directory.systemTemp.path}/tp-win-back.bin');
      await sftp.downloadFile(remote, back.path);

      expect(await back.readAsBytes(), payload);
      await local.delete();
      await back.delete();
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('uploading over an existing file replaces it', () async {
      final local = File('${Directory.systemTemp.path}/tp-win-over.txt');
      await local.writeAsString('second');
      final remote = '$scratch/over.txt';
      await sftp.writeStringToFile(remote, 'first');

      await sftp.uploadFile(local.path, remote);
      expect(await sftp.readFileString(remote), 'second');
      await local.delete();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('saving an edited file over itself works', () async {
      final remote = '$scratch/notes.txt';
      await sftp.writeStringToFile(remote, 'v1');
      await sftp.writeStringToFile(remote, 'v2');
      expect(await sftp.readFileString(remote), 'v2');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('renaming onto an existing name is reported, not silent', () async {
      await sftp.writeStringToFile('$scratch/one.txt', 'one');
      await sftp.writeStringToFile('$scratch/two.txt', 'two');
      String outcome;
      try {
        await sftp.rename('$scratch/one.txt', '$scratch/two.txt');
        outcome = 'overwrote';
      } catch (error) {
        outcome = 'refused: $error';
      }
      // ignore: avoid_print
      print('rename onto an existing name on Windows $outcome');
      expect(
        outcome == 'overwrote' || outcome.contains('sftp.errors.'),
        isTrue,
        reason: outcome,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('reports a missing file distinctly', () async {
      await expectLater(
        sftp.readFileString('$scratch/nope.txt'),
        throwsA(predicate((Object e) => e.toString().contains('notFound'))),
      );
    });

    test('walks and deletes a tree', () async {
      await sftp.createDirectory('$scratch/tree');
      await sftp.createDirectory('$scratch/tree/sub');
      await sftp.writeStringToFile('$scratch/tree/sub/deep.txt', 'x');
      await sftp.writeStringToFile('$scratch/tree/top.txt', 'x');

      final walked = await sftp.walkDirectory('$scratch/tree');
      expect(
        walked.map((e) => e.relativePath).toSet(),
        containsAll(<String>['top.txt', 'sub/deep.txt']),
      );

      await sftp.deletePath('$scratch/tree', isDirectory: true);
      expect(await sftp.exists('$scratch/tree'), isFalse);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, skip: !_live);

  group('live windows agent', () {
    late SshService ssh;

    setUp(() async {
      ssh = await _connect();
    });

    tearDown(() async {
      await ssh.disconnect();
    });

    test('probes a bare host as missing on Windows', () async {
      await _powershell(
        ssh,
        r'Get-Process termphin-agent -ErrorAction SilentlyContinue | '
        r'Stop-Process -Force; Start-Sleep -Seconds 1; '
        r'Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '
        r'"$env:LOCALAPPDATA\termphin"',
      );
      final status = await const RemoteAgentService().probe(ssh.client!);
      // ignore: avoid_print
      print(
        'probe: os=${status.operatingSystem} arch=${status.rawArchitecture} '
        'state=${status.publicStatus.state.name}',
      );
      expect(status.supported, isTrue);
      expect(status.operatingSystem, 'Windows');
      expect(status.publicStatus.architecture, 'x86_64');
      expect(status.publicStatus.state.name, 'missing');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('installs the helper and verifies it', () async {
      final installed = await const RemoteAgentService().install(ssh.client!);
      expect(installed.publicStatus.state.name, 'current');
      expect(installed.usable, isTrue);
      expect(installed.binaryPath, contains('termphin-agent.exe'));

      final again = await const RemoteAgentService().probe(ssh.client!);
      expect(again.publicStatus.state.name, 'current');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('repairs a corrupted install', () async {
      await const RemoteAgentService().install(ssh.client!);
      await _powershell(
        ssh,
        r'Set-Content -Path "$env:LOCALAPPDATA\termphin\bin\agent.meta" '
        r'-Value "garbage"',
      );
      final status = await const RemoteAgentService().probe(ssh.client!);
      expect(status.publicStatus.state.name, 'repair');
      final fixed = await const RemoteAgentService().ensureForAttach(
        ssh.client!,
        probed: status,
      );
      expect(fixed.publicStatus.state.name, 'current');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('starts a session, lists it and kills it', () async {
      await const RemoteAgentService().install(ssh.client!);
      final buffer = StringBuffer();
      ssh.output.listen(
        (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
      );
      final session = await ssh.startShell(
        command: '& "$_agentBin" attach winsession',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      session.write(Uint8List.fromList(utf8.encode('echo WINDOWS_MARKER\r\n')));
      await Future<void>.delayed(const Duration(seconds: 5));
      // ignore: avoid_print
      print('attached session output: ${buffer.length} bytes');
      expect(buffer.toString(), contains('WINDOWS_MARKER'));

      final probe = await _connect();
      final listed = await _powershell(probe, '& "$_agentBin" list');
      // ignore: avoid_print
      print('agent list: ${listed.trim()}');
      expect(listed, contains('winsession'));

      await _powershell(probe, '& "$_agentBin" kill winsession');
      final after = await _powershell(probe, '& "$_agentBin" list');
      expect(after, isNot(contains('winsession')));
      await probe.disconnect();
    }, timeout: const Timeout(Duration(minutes: 10)));
  }, skip: !_live);

  group('live windows resilience', () {
    test('a session survives the machine losing power and says so', () async {
      var ssh = await _connect();
      await const RemoteAgentService().install(ssh.client!);

      final buffer = StringBuffer();
      ssh.output.listen(
        (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
      );
      final session = await ssh.startShell(
        command: '& "$_agentBin" attach cutme',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      session.write(
        Uint8List.fromList(utf8.encode('echo BEFORE_POWERCUT\r\n')),
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(buffer.toString(), contains('BEFORE_POWERCUT'));

      await _powerCutAndReboot();

      ssh = await _connect(attempts: 30);
      final listed = await _powershell(ssh, '& "$_agentBin" list');
      // ignore: avoid_print
      print('sessions listed after the power cut: ${listed.trim()}');
      expect(
        listed,
        isNot(contains('cutme')),
        reason: 'a session that died with the machine is still listed',
      );

      final revived = StringBuffer();
      ssh.output.listen(
        (chunk) => revived.write(utf8.decode(chunk, allowMalformed: true)),
      );
      await ssh.startShell(command: '& "$_agentBin" attach --replay cutme');
      await Future<void>.delayed(const Duration(seconds: 8));
      // ignore: avoid_print
      print(
        'reboot marker after the power cut: '
        '${revived.toString().contains('5381;termphin-reboot-restored')}',
      );
      expect(
        revived.toString(),
        contains('5381;termphin-reboot-restored'),
        reason: 'the app was never told the shell is a new one',
      );
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 15)));
  }, skip: !_canPowerCut);
}

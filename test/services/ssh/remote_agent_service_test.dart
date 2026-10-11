import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/remote_agent_status.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';

/// Returns different canned output depending on whether the command looks
/// like the POSIX probe (`/bin/sh -c ...`) or the PowerShell one, so probe()'s
/// fall-through from one to the other can be exercised without a real host.
class _ScriptedSshClient implements SSHClient {
  _ScriptedSshClient({
    this.posixExitCode = 1,
    this.posixStdout = '',
    this.windowsArch = 'AMD64',
  });

  final int posixExitCode;
  final String posixStdout;
  final String windowsArch;
  final List<String> commands = [];

  @override
  bool get isClosed => false;

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    if (command.startsWith('/bin/sh')) {
      return SSHRunResult(
        output: Uint8List(0),
        stdout: Uint8List.fromList(utf8.encode(posixStdout)),
        stderr: Uint8List.fromList(
          posixExitCode == 0
              ? []
              : utf8.encode(
                  "'/bin/sh' is not recognized as an internal or external command.",
                ),
        ),
        exitCode: posixExitCode,
        exitSignal: null,
      );
    }
    final windowsProbe =
        '''
home=C:\\Users\\Administrator
os=Windows
arch=$windowsArch
binary=0
''';
    return SSHRunResult(
      output: Uint8List(0),
      stdout: Uint8List.fromList(utf8.encode(windowsProbe)),
      stderr: Uint8List(0),
      exitCode: 0,
      exitSignal: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'probe falls back to PowerShell and reports Windows when the POSIX probe fails',
    () async {
      final client = _ScriptedSshClient(posixExitCode: 1);
      const service = RemoteAgentService();

      final status = await service.probe(client);

      expect(
        client.commands.any((command) => command.contains('powershell')),
        isTrue,
      );
      expect(status.operatingSystem, 'Windows');
      expect(status.rawArchitecture, 'AMD64');
      expect(status.publicStatus.architecture, 'x86_64');
      expect(status.publicStatus.operatingSystem, 'Windows');
      expect(status.publicStatus.supported, isTrue);
      expect(status.home, r'C:\Users\Administrator');
    },
  );

  test('probe stays on the POSIX path when it succeeds', () async {
    final client = _ScriptedSshClient(
      posixExitCode: 0,
      posixStdout: 'home=/home/test\nos=Linux\narch=x86_64\nbinary=0\n',
    );
    const service = RemoteAgentService();

    final status = await service.probe(client);

    expect(
      client.commands.any((command) => command.contains('powershell')),
      isFalse,
    );
    expect(status.operatingSystem, 'Linux');
    expect(status.publicStatus.architecture, 'x86_64');
  });

  test('probe reports a Darwin host as supported', () async {
    final client = _ScriptedSshClient(
      posixExitCode: 0,
      posixStdout: 'home=/Users/test\nos=Darwin\narch=arm64\nbinary=0\n',
    );
    const service = RemoteAgentService();

    final status = await service.probe(client);

    expect(status.operatingSystem, 'Darwin');
    expect(status.publicStatus.architecture, 'aarch64');
    expect(status.publicStatus.supported, isTrue);
  });

  test('an ARM64 Windows host is reported unsupported, not an error', () async {
    final client = _ScriptedSshClient(posixExitCode: 1, windowsArch: 'ARM64');
    const service = RemoteAgentService();

    final status = await service.probe(client);

    expect(status.operatingSystem, 'Windows');
    expect(status.rawArchitecture, 'ARM64');
    expect(status.publicStatus.supported, isFalse);
    expect(status.publicStatus.state, RemoteAgentState.unsupported);
  });

  test('ensureForAttach explains an unsupported Windows CPU', () async {
    final client = _ScriptedSshClient(posixExitCode: 1, windowsArch: 'ARM64');
    const service = RemoteAgentService();

    await expectLater(
      service.ensureForAttach(client),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('arch=ARM64'), contains('os=Windows')),
        ),
      ),
    );
  });
}

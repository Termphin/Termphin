import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/session_tab.dart';
import 'package:termphin/services/terminal/remote_mux_commands.dart';

void main() {
  const mux = RemoteMuxCommands();

  group('the attach command', () {
    test('execs the agent on a POSIX host', () {
      expect(
        mux.attachCommand(Multiplexer.termphin, '/opt/agent', 'work', false),
        "exec '/opt/agent' attach 'work'",
      );
    });

    test('asks for a replay when the tab is being picked back up', () {
      expect(
        mux.attachCommand(Multiplexer.termphin, '/opt/agent', 'work', true),
        contains('--replay'),
      );
    });

    test('asks to resume from an offset alongside the replay fallback', () {
      expect(
        mux.attachCommand(
          Multiplexer.termphin,
          '/opt/agent',
          'work',
          true,
          resumeFrom: (epoch: '77', offset: 1234),
        ),
        "exec '/opt/agent' attach --replay --resume 77:1234 'work'",
      );
    });

    test('never asks a Windows agent to resume', () {
      final command = mux.attachCommand(
        Multiplexer.termphin,
        r'C:\agent.exe',
        'work',
        true,
        operatingSystem: 'Windows',
        resumeFrom: (epoch: '77', offset: 1234),
      );
      final script = String.fromCharCodes(
        _utf16le(base64Decode(command.split(' ').last)),
      );
      expect(script, contains('--replay'));
      expect(script, isNot(contains('--resume')));
    });

    test('resumes only on an agent new enough to', () {
      expect(RemoteMuxCommands.agentCanResume('0.12.0'), isTrue);
      expect(RemoteMuxCommands.agentCanResume('1.0.0'), isTrue);
      expect(RemoteMuxCommands.agentCanResume('0.11.9'), isFalse);
      expect(RemoteMuxCommands.agentCanResume(null), isFalse);
      expect(RemoteMuxCommands.agentCanResume('garbage'), isFalse);
    });

    test('quotes a POSIX path that would otherwise word-split', () {
      final command = mux.attachCommand(
        Multiplexer.termphin,
        '/opt/my agent',
        'work',
        false,
      );
      expect(command, contains("'/opt/my agent'"));
    });

    test('goes through PowerShell on Windows, with the call operator', () {
      final command = mux.attachCommand(
        Multiplexer.termphin,
        r'C:\Users\me\agent.exe',
        'work',
        false,
        operatingSystem: 'Windows',
      );
      expect(command, isNot(contains('exec ')));
      expect(command, contains('-EncodedCommand'));

      final encoded = command.split(' ').last;
      final inner = String.fromCharCodes(_utf16le(base64Decode(encoded)));
      expect(inner, startsWith('& '));
      expect(inner, contains(r'C:\Users\me\agent.exe'));
      expect(inner, contains('attach'));
    });

    test('a non-persistent tab has no attach command at all', () {
      expect(
        mux.attachCommand(Multiplexer.none, '/opt/agent', 'work', false),
        isEmpty,
      );
    });
  });

  group('the session list', () {
    test('reads the four tab-separated fields', () {
      final sessions = mux.parseSessionList(
        'work\t2\t1700000000\t1\nbuild\t1\t1700000001\t0\n',
        Multiplexer.termphin,
      );

      expect(sessions.map((s) => s.name), ['work', 'build']);
      expect(sessions.first.windows, 2);
      expect(sessions.first.attached, isTrue);
      expect(sessions.last.attached, isFalse);
    });

    test('skips lines that are not session records', () {
      final sessions = mux.parseSessionList(
        'Welcome to example.com\n\nwork\t1\t1700000000\t0\n',
        Multiplexer.termphin,
      );
      expect(sessions.map((s) => s.name), ['work']);
    });

    test('an empty listing is an empty list, not an error', () {
      expect(mux.parseSessionList('', Multiplexer.termphin), isEmpty);
    });
  });

  group('name validation', () {
    test('accepts an ordinary name', () {
      mux.validateMuxName('termphin_work');
    });

    test('rejects one the agent could not address', () {
      expect(
        () => mux.validateMuxName('work space/../etc'),
        throwsA(isA<Exception>()),
      );
    });
  });
}

/// PowerShell's -EncodedCommand is base64 of UTF-16LE.
Iterable<int> _utf16le(List<int> bytes) sync* {
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    yield bytes[i] | (bytes[i + 1] << 8);
  }
}

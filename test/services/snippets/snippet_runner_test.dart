import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/services/snippets/snippet_runner.dart';

/// Decodes the script body that a staged execution ships to the host.
String stagedScript(String setupCommand) {
  final start = setupCommand.indexOf("'") + 1;
  final end = setupCommand.indexOf("'", start);
  return utf8.decode(base64Decode(setupCommand.substring(start, end)));
}

void main() {
  group('prepareSnippetExecution', () {
    test('sends a plain single-line command straight to the terminal', () {
      final execution = prepareSnippetExecution(
        command: 'uptime',
        shellType: RemoteShellType.unix,
      );
      expect(execution.setupCommand, isNull);
      expect(execution.terminalInput, 'uptime\r');
    });

    test('trims trailing whitespace rather than sending a blank line', () {
      final execution = prepareSnippetExecution(
        command: 'uptime\n',
        shellType: RemoteShellType.unix,
      );
      expect(execution.terminalInput, 'uptime\r');
    });

    test('stages a multi-line body and types only a short command', () {
      final execution = prepareSnippetExecution(
        command: 'echo one\necho two',
        shellType: RemoteShellType.unix,
        scriptId: 'abc',
      );
      expect(execution.terminalInput, "sh '/tmp/.termphin-snippet-abc.sh'\r");
      expect(execution.setupCommand, isNot(contains('echo one')));
      expect(execution.setupCommand, startsWith('printf %s '));
      expect(
        execution.setupCommand,
        endsWith("| base64 -d > '/tmp/.termphin-snippet-abc.sh'"),
      );
      expect(
        stagedScript(execution.setupCommand!),
        contains('echo one\necho two'),
      );
    });

    test('a run id stages even a single line so it can report its status', () {
      final execution = prepareSnippetExecution(
        command: 'uptime',
        shellType: RemoteShellType.unix,
        runId: 'run-1',
        scriptId: 'abc',
      );
      expect(execution.setupCommand, isNotNull);
      expect(execution.terminalInput, "sh '/tmp/.termphin-snippet-abc.sh'\r");
    });

    test('the staged script reports its exit status from an EXIT trap', () {
      final execution = prepareSnippetExecution(
        command: 'false',
        shellType: RemoteShellType.unix,
        runId: 'run-1',
      );
      final script = stagedScript(execution.setupCommand!);
      expect(script, startsWith('trap '));
      expect(script, contains(r'st=$?'));
      expect(script, contains(r'\033]5379;termphin;run-1;%d\007'));
      expect(script, endsWith('false\n'));
    });

    test('the staged script deletes itself on the way out', () {
      final execution = prepareSnippetExecution(
        command: 'echo one\necho two',
        shellType: RemoteShellType.unix,
      );
      final script = stagedScript(execution.setupCommand!);
      expect(script, contains(r'rm -f "$0"'));
    });

    test('a script with no run id carries no marker plumbing', () {
      final execution = prepareSnippetExecution(
        command: 'echo one\necho two',
        shellType: RemoteShellType.unix,
      );
      expect(stagedScript(execution.setupCommand!), isNot(contains('5379')));
    });

    test('marker matches what the output stream is scanned for', () {
      expect(snippetMarker('run-1', 0), ']5379;termphin;run-1;0');
    });

    test('powershell types the body instead of staging it', () {
      final execution = prepareSnippetExecution(
        command: 'Get-Process\nGet-Service',
        shellType: RemoteShellType.powershell,
      );
      expect(execution.setupCommand, isNull);
      expect(execution.terminalInput, 'Get-Process\rGet-Service\r');
    });

    test('powershell defaults a null exit code when reporting', () {
      final execution = prepareSnippetExecution(
        command: 'Get-Process',
        shellType: RemoteShellType.powershell,
        runId: 'run-2',
      );
      expect(execution.setupCommand, isNull);
      expect(
        execution.terminalInput,
        contains(r'if ($null -eq $c) { $c = 0 }'),
      );
      expect(execution.terminalInput, contains(']5379;termphin;run-2;'));
    });

    test('CRLF input is normalized before deciding single vs multi-line', () {
      final execution = prepareSnippetExecution(
        command: 'echo hi\r\n',
        shellType: RemoteShellType.unix,
      );
      expect(execution.setupCommand, isNull);
      expect(execution.terminalInput, 'echo hi\r');
    });
  });
}

@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';

import 'live_env.dart';

/// Live resilience tests: what the remote agent and the SSH layer do when the
/// link dies, the host freezes, or the machine is cut off at the wall.
///
/// Needs TERMPHIN_LIVE_SSH_PORT and TERMPHIN_LIVE_CONTAINER (podman name).
final _portEnv = Platform.environment['TERMPHIN_LIVE_SSH_PORT'];
final _container = Platform.environment['TERMPHIN_LIVE_CONTAINER'] ?? '';
final _live = _portEnv != null && _container.isNotEmpty;
final _port = int.tryParse(_portEnv ?? '') ?? 0;
const _host = '127.0.0.1';
const _user = 'tester';
const _pass = 'testpass';
const _agentBin = '/home/tester/.local/lib/termphin/termphin-agent';

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

Future<SshService> _connect({int attempts = 20}) async {
  Object? last;
  for (var i = 0; i < attempts; i++) {
    final service = SshService();
    try {
      await service.connect(_profile(), onHostKeyPrompt: acceptHostKey);
      return service;
    } catch (error) {
      last = error;
      await service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  throw Exception('could not connect: $last');
}

Future<ProcessResult> _podman(List<String> args) =>
    Process.run('podman', [...args]);

Future<String> _run(SSHClient client, String command) async {
  final result = await client.run(command);
  return utf8.decode(result, allowMalformed: true);
}

/// Attaches to [name] and returns a sink of what the pty prints.
Future<(SSHSession, StringBuffer)> _attach(
  SshService ssh,
  String name, {
  bool replay = false,
}) async {
  final buffer = StringBuffer();
  ssh.output.listen(
    (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
  );
  final session = await ssh.startShell(
    command: replay
        ? "exec '$_agentBin' attach --replay '$name'"
        : "exec '$_agentBin' attach '$name'",
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  return (session, buffer);
}

void _type(SSHSession session, String line) =>
    session.write(Uint8List.fromList(utf8.encode('$line\n')));

Future<void> _waitFor(
  StringBuffer buffer,
  String needle, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (buffer.toString().contains(needle)) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('timed out waiting for "$needle" in:\n${buffer.toString()}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live resilience', () {
    setUpAll(() async {
      initLiveEnv();
      if (!_live) return;
      final ssh = await _connect();
      await const RemoteAgentService().install(ssh.client!);
      await ssh.disconnect();
    });

    setUp(() async {
      final ssh = await _connect();
      await _run(
        ssh.client!,
        "'$_agentBin' list | cut -f1 | "
        "while read n; do '$_agentBin' kill \"\$n\"; done",
      );
      await ssh.disconnect();
    });

    test('work keeps running after the client disconnects', () async {
      var ssh = await _connect();
      final (session, buffer) = await _attach(ssh, 'work');
      _type(session, 'echo MARKER_ONE');
      await _waitFor(buffer, 'MARKER_ONE');
      _type(
        session,
        r'(i=0; while :; do i=$((i+1)); echo $i > ~/counter; sleep 0.2; '
        'done) >/dev/null 2>&1 &',
      );
      await Future<void>.delayed(const Duration(seconds: 2));

      await ssh.disconnect();
      await Future<void>.delayed(const Duration(seconds: 4));

      ssh = await _connect();
      final first = int.tryParse(
        (await _run(ssh.client!, 'cat ~/counter')).trim(),
      );
      expect(first, isNotNull, reason: 'background job died with the client');
      await Future<void>.delayed(const Duration(seconds: 2));
      final second = int.tryParse(
        (await _run(ssh.client!, 'cat ~/counter')).trim(),
      );
      expect(second! > first!, isTrue, reason: 'job stopped after disconnect');

      final listed = await _run(ssh.client!, "'$_agentBin' list");
      expect(listed, contains('work'));
      expect(
        listed.split('\t').last.trim(),
        '0',
        reason: 'session still reports an attached client',
      );

      final (_, replayed) = await _attach(ssh, 'work', replay: true);
      await _waitFor(replayed, 'MARKER_ONE');
      await _run(ssh.client!, r'pkill -f "while :" || true');
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('survives the server killing the connection mid-session', () async {
      var ssh = await _connect();
      var lost = 0;
      ssh.onConnectionLost = () => lost++;
      final (session, buffer) = await _attach(ssh, 'killed');
      _type(session, 'echo BEFORE_KILL');
      await _waitFor(buffer, 'BEFORE_KILL');
      ssh.startHealthCheck();

      final killed = await _podman([
        'exec',
        _container,
        'pkill',
        '-9',
        '-f',
        'sshd: tester',
      ]);
      expect(killed.exitCode, 0, reason: 'nothing matched the sshd child');
      await Future<void>.delayed(const Duration(seconds: 2));

      ssh.write(Uint8List.fromList(utf8.encode('echo AFTER\n')));
      final wroteBlind = lost == 0;

      final start = DateTime.now();
      while (lost == 0 &&
          DateTime.now().difference(start) < const Duration(seconds: 40)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final latency = DateTime.now().difference(start);
      // ignore: avoid_print
      print(
        'connection-loss detection: ${latency.inMilliseconds}ms after the '
        'kill, write-before-detection swallowed: $wroteBlind',
      );
      expect(lost, greaterThan(0), reason: 'connection loss went unnoticed');
      await ssh.disconnect();

      ssh = await _connect();
      final listed = await _run(ssh.client!, "'$_agentBin' list");
      expect(listed, contains('killed'), reason: 'session died with the link');
      final (_, replayed) = await _attach(ssh, 'killed', replay: true);
      await _waitFor(replayed, 'BEFORE_KILL');
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('notices a frozen host through the health check', () async {
      final ssh = await _connect();
      var lost = 0;
      ssh.onConnectionLost = () => lost++;
      await _attach(ssh, 'frozen');
      ssh.startHealthCheck();

      await _podman(['pause', _container]);
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (lost == 0 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      } finally {
        await _podman(['unpause', _container]);
      }
      expect(
        lost,
        greaterThan(0),
        reason: 'a frozen host never tripped the health check',
      );
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('a hard power cut leaves no phantom sessions behind', () async {
      var ssh = await _connect();
      final (session, buffer) = await _attach(ssh, 'doomed');
      _type(session, 'echo BEFORE_POWERCUT');
      await _waitFor(buffer, 'BEFORE_POWERCUT');
      final before = await _run(ssh.client!, "'$_agentBin' list");
      expect(before, contains('doomed'));

      await _podman(['kill', '-s', 'KILL', _container]);
      await Future<void>.delayed(const Duration(seconds: 2));
      await _podman(['start', _container]);
      await Future<void>.delayed(const Duration(seconds: 3));

      ssh = await _connect();
      final after = await _run(ssh.client!, "'$_agentBin' list");
      expect(
        after.trim(),
        isEmpty,
        reason: 'dead sessions still listed after a power cut: $after',
      );

      final (revived, revivedBuffer) = await _attach(ssh, 'doomed');
      _type(revived, 'echo AFTER_POWERCUT');
      await _waitFor(revivedBuffer, 'AFTER_POWERCUT');
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('killing the agent process ends the attached shell cleanly', () async {
      final ssh = await _connect();
      final (session, buffer) = await _attach(ssh, 'victim');
      _type(session, 'echo ALIVE');
      await _waitFor(buffer, 'ALIVE');

      await _podman([
        'exec',
        _container,
        'pkill',
        '-9',
        '-f',
        'termphin-agent',
      ]);
      await session.done.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail('attached shell never ended with the agent'),
      );

      final probe = await _connect();
      final listed = await _run(probe.client!, "'$_agentBin' list");
      expect(
        listed,
        isNot(contains('victim')),
        reason: 'killed session still listed',
      );
      await probe.disconnect();
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('two clients can attach the same session', () async {
      final first = await _connect();
      final (a, bufferA) = await _attach(first, 'shared');
      _type(a, 'echo FROM_FIRST');
      await _waitFor(bufferA, 'FROM_FIRST');

      final second = await _connect();
      final (b, bufferB) = await _attach(second, 'shared', replay: true);
      await _waitFor(bufferB, 'FROM_FIRST');
      _type(b, 'echo FROM_SECOND');
      await _waitFor(bufferB, 'FROM_SECOND');
      await _waitFor(bufferA, 'FROM_SECOND');

      await first.disconnect();
      await second.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'attaching a name that no longer exists starts a fresh session',
      () async {
        final ssh = await _connect();
        final (session, buffer) = await _attach(ssh, 'ghost');
        _type(session, 'echo FRESH_GHOST');
        await _waitFor(buffer, 'FRESH_GHOST');
        final listed = await _run(ssh.client!, "'$_agentBin' list");
        expect(listed, contains('ghost'));
        await ssh.disconnect();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('agent survives sshd restarting under it', () async {
      var ssh = await _connect();
      final (session, buffer) = await _attach(ssh, 'sshdrestart');
      _type(session, 'echo BEFORE_SSHD');
      await _waitFor(buffer, 'BEFORE_SSHD');

      await _podman(['exec', _container, 'pkill', '-HUP', 'sshd']);
      await Future<void>.delayed(const Duration(seconds: 3));
      await ssh.disconnect();

      ssh = await _connect();
      final listed = await _run(ssh.client!, "'$_agentBin' list");
      expect(listed, contains('sshdrestart'));
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('scrollback kept for a detached session is bounded', () async {
      final ssh = await _connect();
      final (session, buffer) = await _attach(ssh, 'noisy');
      _type(session, 'echo READY');
      await _waitFor(buffer, 'READY');
      _type(session, 'head -c 20000000 /dev/urandom | base64');
      await Future<void>.delayed(const Duration(seconds: 25));
      final size = (await _run(
        ssh.client!,
        'du -sk ~/.cache/termphin/sessions/noisy | cut -f1',
      )).trim();
      // ignore: avoid_print
      print('session state on disk after 20MB of output: ${size}KB');
      final leftovers = await _run(
        ssh.client!,
        'ls ~/.cache/termphin/sessions | wc -l',
      );
      // ignore: avoid_print
      print('session directories on the server: ${leftovers.trim()}');
      expect(int.tryParse(size) ?? 0, lessThan(20000));
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('a session revived after a reboot announces itself', () async {
      var ssh = await _connect();
      final (session, buffer) = await _attach(ssh, 'rebooter');
      _type(session, 'cd /tmp && echo IN_TMP');
      await _waitFor(buffer, 'IN_TMP');
      await Future<void>.delayed(const Duration(seconds: 2));

      await _podman(['kill', '-s', 'KILL', _container]);
      await Future<void>.delayed(const Duration(seconds: 2));
      await _podman(['start', _container]);
      await Future<void>.delayed(const Duration(seconds: 3));
      ssh = await _connect();
      await _run(
        ssh.client!,
        'echo 00000000-0000-0000-0000-000000000000 > '
        r'$HOME/.cache/termphin/sessions/rebooter/boot_id',
      );

      final (revived, revivedBuffer) = await _attach(
        ssh,
        'rebooter',
        replay: true,
      );
      _type(revived, 'pwd');
      await _waitFor(revivedBuffer, '/tmp');
      expect(
        revivedBuffer.toString(),
        contains('5381;termphin-reboot-restored'),
        reason: 'the app was never told the shell is a new one',
      );
      expect(revivedBuffer.toString(), contains('after a server restart'));
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 4)));

    test(
      'a session recreated after the agent dies announces itself too',
      () async {
        var ssh = await _connect();
        final (session, buffer) = await _attach(ssh, 'crashed');
        _type(session, 'cd /tmp && export MARKER_VAR=set && echo IN_TMP');
        await _waitFor(buffer, 'IN_TMP');
        await Future<void>.delayed(const Duration(seconds: 2));

        await _podman(['kill', '-s', 'KILL', _container]);
        await Future<void>.delayed(const Duration(seconds: 2));
        await _podman(['start', _container]);
        await Future<void>.delayed(const Duration(seconds: 3));

        ssh = await _connect();
        final (revived, revivedBuffer) = await _attach(
          ssh,
          'crashed',
          replay: true,
        );
        _type(revived, r'echo "VAR=[$MARKER_VAR]"');
        await _waitFor(revivedBuffer, 'VAR=[');
        expect(
          revivedBuffer.toString(),
          contains('VAR=[]'),
          reason: 'shell state unexpectedly survived',
        );
        expect(
          revivedBuffer.toString(),
          contains('5381;termphin-reboot-restored'),
          reason: 'the session was silently recreated with no notice',
        );
        expect(revivedBuffer.toString(), contains('previous shell is gone'));
        await ssh.disconnect();
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test('a probe still reports current after a power cut', () async {
      await _podman(['kill', '-s', 'KILL', _container]);
      await Future<void>.delayed(const Duration(seconds: 2));
      await _podman(['start', _container]);
      final ssh = await _connect();
      final status = await const RemoteAgentService().probe(ssh.client!);
      expect(status.publicStatus.state.name, 'current');
      await ssh.disconnect();
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: !_live);
}

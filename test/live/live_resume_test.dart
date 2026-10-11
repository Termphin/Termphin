@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import 'live_env.dart';

/// A dropped session picking its output up where it stopped, through the
/// real manager, sshd and agent.
///
/// Needs TERMPHIN_LIVE_SSH_PORT and TERMPHIN_LIVE_CONTAINER, and an agent of
/// 0.12.0 or later installed for `tester` with a matching `agent.meta` - the
/// bundled one predates `--resume`, and the manager leaves a newer one alone.
final _portEnv = Platform.environment['TERMPHIN_LIVE_SSH_PORT'];
final _container = Platform.environment['TERMPHIN_LIVE_CONTAINER'] ?? '';
final _live = _portEnv != null && _container.isNotEmpty;

SshProfile _profile() => SshProfile(
  id: 'live-resume',
  name: 'live-resume',
  host: '127.0.0.1',
  port: int.tryParse(_portEnv ?? '') ?? 0,
  username: 'tester',
  authMethod: AuthMethod.password,
  password: 'testpass',
  createdAt: DateTime.now(),
);

/// Cuts every SSH connection `tester` has, the way a lost network would look
/// to the server - the agent's master, detached from them, stays up.
Future<void> _cutConnections() async {
  await Process.run('podman', [
    'exec',
    _container,
    'pkill',
    '-KILL',
    '-f',
    'sshd: tester',
  ]);
}

Future<void> _agent(String args) async {
  await Process.run('podman', [
    'exec',
    _container,
    'su',
    'tester',
    '-c',
    '/home/tester/.local/lib/termphin/termphin-agent $args',
  ]);
}

void main() {
  late SshSessionManager manager;
  late StringBuffer screen;
  late StreamSubscription<List<int>> watching;

  setUpAll(() async {
    initLiveEnv();
    await loadAppSettings();
  });

  setUp(() {
    manager = SshSessionManager.test()..hostKeyPrompt = acceptHostKey;
    screen = StringBuffer();
  });

  tearDown(() async {
    await watching.cancel();
    manager.dispose();
    await _agent('kill live-resume');
  });

  Future<ActiveSessionView> start({bool resume = false}) =>
      manager.startSession(
        _profile(),
        sessionId: 'tab',
        muxName: 'live-resume',
        replayRemoteHistory: true,
        resume: resume,
      );

  Future<void> waitFor(String text) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!screen.toString().contains(text)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('"$text" never arrived. Screen:\n$screen');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> type(String text) async =>
      manager.sendInput('tab', utf8.encode(text));

  Future<void> waitForDrop(ActiveSessionView session) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!session.dropped) {
      if (DateTime.now().isAfter(deadline)) fail('the drop was never seen');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test(
    'a drop is continued on the same terminal with only what was missed',
    () async {
      final session = await start();
      watching = session.outputStream.listen(
        (bytes) => screen.write(utf8.decode(bytes, allowMalformed: true)),
      );
      expect(session.outputPosition, isNotNull);

      await type('echo before-\$((40+2))\r');
      await waitFor('before-42');
      await type('(sleep 2; echo while-away-\$((3+4))) &\r');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await _cutConnections();
      await waitForDrop(session);
      await Future<void>.delayed(const Duration(seconds: 3));

      final resumed = await start(resume: true);

      expect(resumed, same(session));
      expect(resumed.resumedInPlace, isTrue);
      await waitFor('while-away-7');
      expect(
        'before-42'.allMatches(screen.toString()),
        hasLength(1),
        reason: 'the output once - a replay would have drawn it again',
      );

      await type('echo after-\$((5+5))\r');
      await waitFor('after-10');
    },
    skip: _live ? false : 'TERMPHIN_LIVE_* not set',
  );

  test('a flood written while away arrives whole, once and in order', () async {
    final session = await start();
    watching = session.outputStream.listen(
      (bytes) => screen.write(utf8.decode(bytes, allowMalformed: true)),
    );
    await type('stty -echo; echo ready\r');
    await waitFor('ready');
    await type('(sleep 1; seq -f line-%g 1 15000; echo flood-done) &\r');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await _cutConnections();
    await waitForDrop(session);
    await Future<void>.delayed(const Duration(seconds: 3));

    final resumed = await start(resume: true);
    expect(resumed.resumedInPlace, isTrue);
    await waitFor('flood-done');

    final lines = RegExp(
      r'line-(\d+)',
    ).allMatches(screen.toString()).map((m) => int.parse(m.group(1)!));
    expect(lines, [for (var i = 1; i <= 15000; i++) i]);
  }, skip: _live ? false : 'TERMPHIN_LIVE_* not set');

  test('a master that was restarted under the same name is replayed', () async {
    final session = await start();
    watching = session.outputStream.listen(
      (bytes) => screen.write(utf8.decode(bytes, allowMalformed: true)),
    );
    await type('echo first-master\r');
    await waitFor('first-master');

    await _cutConnections();
    await waitForDrop(session);
    await _agent('kill live-resume');

    final resumed = await start(resume: true);

    expect(
      resumed.resumedInPlace,
      isFalse,
      reason: "the old position is in the old master's numbering",
    );
  }, skip: _live ? false : 'TERMPHIN_LIVE_* not set');
}

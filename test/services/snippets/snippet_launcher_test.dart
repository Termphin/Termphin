import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/services/snippets/snippet_launcher.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';
import '../../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSshBackend backend;
  late SshSessionManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeSshBackend();
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(backend),
      serviceFactory: backend.createService,
    );
    await manager.startSession(profileFixture(), sessionId: 'session');
    backend.calls.clear();
  });

  tearDown(() => manager.dispose());

  Future<void> launch(String command, {String? runId}) => launchSnippet(
    manager: manager,
    sessionId: 'session',
    command: command,
    shellType: RemoteShellType.unix,
    runId: runId,
  );

  List<MethodCall> callsOf(String method) =>
      backend.calls.where((c) => c.method == method).toList();

  String typed() => [
    for (final call in callsOf('write'))
      utf8.decode((call.arguments as Map)['data'] as Uint8List),
  ].join();

  test('a one-liner is typed into the session and nothing else', () async {
    await launch('ls -la');

    expect(callsOf('exec'), isEmpty, reason: 'nothing to stage');
    expect(typed(), contains('ls -la'));
  });

  test('a multi-line snippet is staged over exec, not typed', () async {
    const body = 'set -e\necho one\necho two';
    await launch(body);

    expect(callsOf('exec'), hasLength(1));
    expect(typed(), isNot(contains('echo two')));
  });

  test('what is typed is short enough to look typed', () async {
    final body = 'set -e\n${'echo padding\n' * 50}';
    await launch(body);

    expect(typed().length, lessThan(body.length));
  });

  test(
    'staging goes first, so the command it kicks off exists by then',
    () async {
      await launch('echo one\necho two');

      expect(backend.calls.map((c) => c.method).toList(), ['exec', 'write']);
    },
  );

  test('a run id stages even a single line, so it can be tracked', () async {
    await launch('ls', runId: 'run-1');

    expect(callsOf('exec'), hasLength(1));
  });

  test('the staged body and the typed command name the same script', () async {
    await launch('echo one\necho two');

    final staged =
        (callsOf('exec').single.arguments as Map)['command'] as String;
    final script = RegExp(r'/tmp/[\w.\-]+\.sh').firstMatch(staged)?.group(0);
    expect(script, isNotNull);
    expect(typed(), contains(script!));

    final encoded = RegExp("'([A-Za-z0-9+/=]+)'").firstMatch(staged)!.group(1)!;
    expect(utf8.decode(base64Decode(encoded)), contains('echo two'));
  });

  test(
    'a staging failure throws instead of half-running the snippet',
    () async {
      backend.execError = Exception('no channel');

      await expectLater(
        launch('echo one\necho two'),
        throwsA(isA<Exception>()),
      );
      expect(callsOf('write'), isEmpty);
    },
  );
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/snippet.dart';
import 'package:termphin/models/snippet_run.dart';
import 'package:termphin/providers/snippet_runs_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../support/fixtures.dart';
import '../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSshBackend backend;
  late FakeRemoteAgentService remoteAgentService;

  Snippet snippetFixture({String command = 'uptime'}) => Snippet(
    id: 'snip-1',
    name: 'Uptime',
    command: command,
    createdAt: DateTime(2026),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeSshBackend();
    remoteAgentService = FakeRemoteAgentService(backend);
  });

  Future<(ProviderContainer, SshSessionManager)> buildContainer() async {
    final manager = SshSessionManager.test(
      remoteAgentService: remoteAgentService,
      serviceFactory: backend.createService,
    );
    await manager.init();
    final container = ProviderContainer(
      overrides: [sshSessionManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);
    addTearDown(manager.dispose);
    return (container, manager);
  }

  test('starts one snippet-run session per machine', () async {
    final (container, manager) = await buildContainer();
    final profiles = [
      profileFixture(id: 'p1', name: 'alpha'),
      profileFixture(id: 'p2', name: 'beta'),
    ];

    container
        .read(snippetRunsProvider.notifier)
        .start(snippet: snippetFixture(), profiles: profiles);
    await pumpEventQueue();

    final batch = container.read(snippetRunsProvider).single;
    expect(batch.runs.map((r) => r.profileName), ['alpha', 'beta']);
    expect(
      batch.runs.every((r) => r.status == SnippetRunStatus.running),
      isTrue,
    );

    final sessions = manager.snippetRunSessions;
    expect(sessions.length, 2);
    expect(sessions.every((session) => session.muxName == null), isTrue);
    expect(sessions.map((session) => session.id).toSet().length, 2);
  });

  test('stages the script over exec and types only a short command', () async {
    final (container, _) = await buildContainer();

    container
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: snippetFixture(),
          profiles: [profileFixture(id: 'p1', name: 'alpha')],
        );
    await pumpEventQueue();

    final exec = backend.calls.lastWhere((call) => call.method == 'exec');
    expect(
      (exec.arguments as Map)['command'] as String,
      contains('base64 -d >'),
    );

    final write = backend.calls.lastWhere((call) => call.method == 'write');
    final typed = String.fromCharCodes(
      (write.arguments as Map)['data'] as List<int>,
    );
    expect(typed, startsWith('sh '));
    expect(typed, endsWith('\r'));
    expect(typed, isNot(contains('5379')));
    expect(typed.length, lessThan(80));
  });

  test('a failed staging marks the run as never started', () async {
    backend.execError = Exception('no shell');
    final (container, _) = await buildContainer();

    container
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: snippetFixture(),
          profiles: [profileFixture(id: 'p1', name: 'alpha')],
        );
    await pumpEventQueue();

    final run = container.read(snippetRunsProvider).single.runs.single;
    expect(run.status, SnippetRunStatus.error);
    expect(backend.calls.where((call) => call.method == 'write'), isEmpty);
  });

  test('resolves placeholders once for the whole batch', () async {
    final (container, _) = await buildContainer();

    container
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: snippetFixture(command: 'systemctl restart {{unit}}'),
          profiles: [profileFixture(id: 'p1', name: 'alpha')],
          argValues: {'unit': 'nginx'},
        );
    await pumpEventQueue();

    expect(
      container.read(snippetRunsProvider).single.command,
      'systemctl restart nginx',
    );
  });

  test('a completion marker settles the matching run', () async {
    final (container, _) = await buildContainer();

    container
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: snippetFixture(),
          profiles: [profileFixture(id: 'p1', name: 'alpha')],
        );
    await pumpEventQueue();
    final runId = container.read(snippetRunsProvider).single.runs.single.id;

    backend.latestService.emit(utf8.encode('\x1b]5379;termphin;$runId;3\x07'));
    await Future<void>.delayed(Duration.zero);

    final run = container.read(snippetRunsProvider).single.runs.single;
    expect(run.status, SnippetRunStatus.failed);
    expect(run.exitCode, 3);
  });

  test('a replayed marker does not reopen a settled run', () async {
    final (container, _) = await buildContainer();

    container
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: snippetFixture(),
          profiles: [profileFixture(id: 'p1', name: 'alpha')],
        );
    await pumpEventQueue();
    final runId = container.read(snippetRunsProvider).single.runs.single.id;

    void deliver(int exitCode) => backend.latestService.emit(
      utf8.encode('\x1b]5379;termphin;$runId;$exitCode\x07'),
    );

    deliver(0);
    await Future<void>.delayed(Duration.zero);
    final settledAt = container
        .read(snippetRunsProvider)
        .single
        .runs
        .single
        .finishedAt;
    deliver(9);
    await Future<void>.delayed(Duration.zero);

    final run = container.read(snippetRunsProvider).single.runs.single;
    expect(run.status, SnippetRunStatus.succeeded);
    expect(run.exitCode, 0);
    expect(run.finishedAt, settledAt);
  });

  test(
    'a run never reaches the tab bar and is torn down when it ends',
    () async {
      final (container, manager) = await buildContainer();

      container
          .read(snippetRunsProvider.notifier)
          .start(
            snippet: snippetFixture(),
            profiles: [profileFixture(id: 'p1', name: 'alpha')],
          );
      await pumpEventQueue();
      final run = container.read(snippetRunsProvider).single.runs.single;

      expect(manager.getSession(run.sessionId)?.isRun, isTrue);
      expect(manager.tabs, isEmpty);

      backend.latestService.emit(utf8.encode('hello\r\n'));
      backend.latestService.emit(
        utf8.encode('\x1b]5379;termphin;${run.id};0\x07'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final settled = container.read(snippetRunsProvider).single.runs.single;
      expect(settled.status, SnippetRunStatus.succeeded);
      expect(settled.output, contains('hello'));
      expect(manager.hasSession(run.sessionId), isFalse);
      expect(manager.tabs, isEmpty);
    },
  );

  test('forgetting a batch closes the sessions it still holds', () async {
    final (container, manager) = await buildContainer();

    container
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: snippetFixture(),
          profiles: [profileFixture(id: 'p1', name: 'alpha')],
        );
    await pumpEventQueue();
    final batchId = container.read(snippetRunsProvider).single.id;

    container.read(snippetRunsProvider.notifier).forget(batchId);

    await Future<void>.delayed(Duration.zero);
    expect(container.read(snippetRunsProvider), isEmpty);
    expect(manager.snippetRunSessions, isEmpty);
  });
}

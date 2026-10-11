import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/remote_agent_status.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/ssh_fakes.dart';

/// Covers the helper hand-off: a tab keeps one stable persistent session name
/// across process restarts, so reconnecting re-attaches instead of spawning a
/// second remote session.
///
/// Two regressions guarded here: `_restoreOfflineTabs()` used to skip any
/// detached tab after a real process restart, so a profile with two detached
/// tabs showed only one of them; and `stopSession()` used to delete the
/// `ActiveSessionView` outright instead of flipping it to dropped, so a
/// detached tab vanished from the profile's row list until the next restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSshBackend backend;
  late FakeRemoteAgentService remoteAgentService;

  SshSessionManager buildManager() => SshSessionManager.test(
    remoteAgentService: remoteAgentService,
    serviceFactory: backend.createService,
  );

  setUp(() {
    mockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    backend = FakeSshBackend();
    remoteAgentService = FakeRemoteAgentService(backend);
  });

  test('keeps snippet runs out of the tab bar', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    await manager.startSession(profile, sessionId: 'tab-1');
    final run = await manager.startSession(
      profile,
      sessionId: 'run-1',
      isRun: true,
    );

    expect(run.muxName, isNull);
    expect(run.multiplexer, Multiplexer.none);
    expect(manager.tabs.map((s) => s.id), ['tab-1']);
    expect(manager.snippetRunSessions.map((s) => s.id), ['run-1']);
    expect(manager.activeCount, 1);
    expect(manager.allTabsForProfile(profile.id).map((s) => s.id), ['tab-1']);
    expect(manager.resumableTabsForProfile(profile.id), isEmpty);
    manager.dispose();
  });

  test('ending a run session forgets it entirely', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    await manager.startSession(profile, sessionId: 'run-1', isRun: true);
    await manager.endRunSession('run-1');

    expect(manager.hasSession('run-1'), isFalse);
    expect(manager.snippetRunSessions, isEmpty);
    manager.dispose();
  });

  test('sends a generated helper session name on the first connect', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    final session = await manager.startSession(profile, sessionId: 'tab-1');

    final muxName = session.muxName!;
    expect(muxName, startsWith('termphin_'));
    expect(muxName, isNot(contains('.')));
    expect(muxName, isNot(contains(':')));
    expect(session.muxName, muxName);
    expect(session.multiplexer, Multiplexer.termphin);
    manager.dispose();
  });

  test(
    're-attaches to the same helper session after a process restart',
    () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);

      final first = buildManager();
      await first.init();
      final original = await first.startSession(profile, sessionId: 'tab-1');
      await first.setActiveSession('tab-1');
      final originalMuxName = original.muxName!;
      first.dispose();

      final second = buildManager();
      await second.init();

      final restored = second.getSession('tab-1');
      expect(restored, isNotNull, reason: 'tab should be restored from disk');
      expect(restored!.dropped, isTrue, reason: 'restored tab starts offline');
      expect(second.tabs.map((tab) => tab.id), ['tab-1']);
      expect(second.activeSessions, isEmpty);
      expect(second.lastSession?.id, 'tab-1');
      expect(second.lastSession?.dropped, isTrue);
      expect(second.resumableTabIdForProfile(profile.id), 'tab-1');

      final reattached = await second.startSession(profile, sessionId: 'tab-1');
      expect(reattached.muxName, originalMuxName);
      second.dispose();
    },
  );

  test('a second tab on the same host gets its own helper session', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    final first = await manager.startSession(profile, sessionId: 'tab-1');
    final firstName = first.muxName;
    final second = await manager.startSession(profile, sessionId: 'tab-2');
    final secondName = second.muxName;

    expect(firstName, isNot(secondName));
    manager.dispose();
  });

  test('detached tabs survive a restart as a resumable offline row', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);

    final first = buildManager();
    await first.init();
    final session = await first.startSession(profile, sessionId: 'tab-1');
    final muxName = session.muxName!;
    await first.stopSession('tab-1');
    first.dispose();

    final second = buildManager();
    await second.init();
    expect(second.tabs.map((s) => s.id), ['tab-1']);
    expect(second.tabs.single.dropped, isTrue);
    expect(second.allTabsForProfile(profile.id).map((s) => s.id), ['tab-1']);
    expect(second.resumableTabIdForProfile(profile.id), 'tab-1');

    final resumed = await second.startSession(profile, sessionId: 'tab-1');
    expect(resumed.muxName, muxName);
    second.dispose();
  });

  test(
    'two detached tabs on the same machine both survive a restart',
    () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);

      final first = buildManager();
      await first.init();
      await first.startSession(profile, sessionId: 'tab-1');
      await first.startSession(profile, sessionId: 'tab-2');
      await first.stopSession('tab-1');
      await first.stopSession('tab-2');
      first.dispose();

      final second = buildManager();
      await second.init();
      expect(second.allTabsForProfile(profile.id).map((s) => s.id).toSet(), {
        'tab-1',
        'tab-2',
      });
      expect(
        second.allTabsForProfile(profile.id).every((s) => s.dropped),
        isTrue,
      );
      second.dispose();
    },
  );

  test(
    'detaching keeps the session visible (as offline) in the same process',
    () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();

      final session = await manager.startSession(profile, sessionId: 'tab-1');
      await manager.setActiveSession('tab-1');
      final muxName = session.muxName!;
      await manager.stopSession('tab-1');

      final tabs = manager.allTabsForProfile(profile.id);
      expect(tabs, hasLength(1));
      expect(tabs.single.id, 'tab-1');
      expect(tabs.single.dropped, isTrue);
      expect(tabs.single.muxName, muxName);
      expect(manager.getSession('tab-1'), isNotNull);
      expect(manager.activeSessions, isEmpty);
      expect(manager.lastSession, isNull);
      manager.dispose();
    },
  );

  test('ending a session removes it from the profile session list', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    await manager.startSession(profile, sessionId: 'tab-1');
    await manager.endSession('tab-1');

    expect(manager.allTabsForProfile(profile.id), isEmpty);
    expect(manager.getSession('tab-1'), isNull);
    manager.dispose();
  });

  test('ending a session forgets the tab and kills it remotely', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);

    final first = buildManager();
    await first.init();
    await first.startSession(profile, sessionId: 'tab-1');
    await first.endSession('tab-1');
    expect(
      backend.calls
          .where((call) => call.method == 'runWithResult')
          .map((call) => (call.arguments as Map)['command']),
      contains(contains(' kill ')),
    );
    first.dispose();

    final second = buildManager();
    await second.init();
    expect(second.tabs, isEmpty);
    expect(second.resumableTabIdForProfile(profile.id), isNull);
    second.dispose();
  });

  group('ending a session', () {
    SSHRunResult exited(int code, [String stderr = '']) => SSHRunResult(
      output: Uint8List(0),
      stdout: Uint8List(0),
      stderr: Uint8List.fromList(utf8.encode(stderr)),
      exitCode: code,
      exitSignal: null,
    );

    Iterable<String> killsSent() => backend.calls
        .where((call) => call.method == 'runWithResult')
        .map((call) => (call.arguments as Map)['command'] as String)
        .where((command) => command.contains(' kill '));

    int connects() =>
        backend.calls.where((call) => call.method == 'connect').length;

    test('forgets the tab before the server answers', () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();
      await manager.startSession(profile, sessionId: 'tab-1');
      final answer = Completer<SSHRunResult>();
      backend.runWithResult = (_) => answer.future;

      final ending = manager.endSession('tab-1');
      await pumpEventQueue();

      expect(killsSent(), hasLength(1));
      expect(manager.getSession('tab-1'), isNull);
      expect(manager.allTabsForProfile(profile.id), isEmpty);
      expect(backend.latestService.connected, isTrue);

      answer.complete(exited(0));
      await ending;
      expect(backend.latestService.connected, isFalse);
      manager.dispose();
    });

    test('reuses the attached agent instead of probing for it', () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();
      await manager.startSession(profile, sessionId: 'tab-1');
      backend.calls.clear();

      await manager.endSession('tab-1');

      expect(
        backend.calls.map((call) => call.method),
        isNot(anyOf(contains('probeAgent'), contains('ensureAgent'))),
      );
      expect(
        killsSent().single,
        startsWith("'${remoteAgentService.status.binaryPath}' kill "),
      );
      manager.dispose();
    });

    test('reports a kill the server refused, with the tab gone', () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();
      await manager.startSession(profile, sessionId: 'tab-1');
      backend.runWithResult = (_) async => exited(1, 'permission denied');

      await expectLater(
        manager.endSession('tab-1'),
        throwsA(
          isA<Exception>().having(
            (error) => '$error',
            'message',
            contains('permission denied'),
          ),
        ),
      );
      expect(manager.getSession('tab-1'), isNull);
      expect(backend.services.single.connected, isFalse);
      manager.dispose();
    });

    void stallFirstKill(
      FutureOr<SSHRunResult> Function(String command) afterwards,
    ) {
      var first = true;
      backend.runWithResult = (command) async {
        if (first && command.contains(' kill ')) {
          first = false;
          return Completer<SSHRunResult>().future;
        }
        return afterwards(command);
      };
    }

    Future<SshSessionManager> started(SshProfile profile) async {
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();
      await manager.startSession(profile, sessionId: 'tab-1');
      return manager;
    }

    test('retries a stalled kill over a fresh connection', () async {
      final profile = profileFixture();
      final manager = await started(profile);
      stallFirstKill((_) => exited(0));
      final before = connects();

      fakeAsync((async) {
        Object? failure;
        var done = false;
        manager
            .endSession('tab-1')
            .then<void>((_) => done = true, onError: (Object e) => failure = e);
        async.flushMicrotasks();
        expect(done, isFalse);
        expect(connects(), before);

        async.elapse(const Duration(seconds: 9));

        expect(failure, isNull);
        expect(done, isTrue);
        expect(connects(), before + 1);
        expect(killsSent(), hasLength(2));
      });
      manager.dispose();
    });

    test('counts a retry that finds the session gone as ended', () async {
      final profile = profileFixture();
      final manager = await started(profile);
      backend.remoteSessionList = 'termphin_other\t1\t1700000000\t0\n';
      stallFirstKill((_) => exited(1, 'No such file or directory'));

      fakeAsync((async) {
        Object? failure;
        var done = false;
        manager
            .endSession('tab-1')
            .then<void>((_) => done = true, onError: (Object e) => failure = e);
        async.elapse(const Duration(seconds: 9));

        expect(failure, isNull);
        expect(done, isTrue);
      });
      manager.dispose();
    });

    test('reports a retry that leaves the session running', () async {
      final profile = profileFixture();
      final manager = await started(profile);
      final muxName = manager.getSession('tab-1')!.muxName!;
      backend.remoteSessionList = '$muxName\t1\t1700000000\t0\n';
      stallFirstKill((_) => exited(1, 'agent busy'));

      fakeAsync((async) {
        Object? failure;
        manager
            .endSession('tab-1')
            .then<void>((_) {}, onError: (Object e) => failure = e);
        async.elapse(const Duration(seconds: 9));

        expect('$failure', contains('agent busy'));
      });
      manager.dispose();
    });

    test('a detached tab leaves before the server is reached', () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();
      await manager.startSession(profile, sessionId: 'tab-1');
      final muxName = manager.getSession('tab-1')!.muxName!;
      await manager.stopSession('tab-1');
      backend.connectGate = Completer<void>();
      backend.calls.clear();

      final killing = manager.killRemoteSession(profile, muxName);
      await pumpEventQueue();

      expect(manager.allTabsForProfile(profile.id), isEmpty);
      expect(killsSent(), isEmpty);

      backend.connectGate!.complete();
      await killing;
      expect(killsSent(), hasLength(1));
      manager.dispose();
    });

    test('never installs the agent just to kill a session', () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();
      remoteAgentService.state = RemoteAgentState.updateAvailable;
      backend.calls.clear();

      await manager.killRemoteSession(profile, 'termphin_abc123');

      final methods = backend.calls.map((call) => call.method);
      expect(methods, contains('probeAgent'));
      expect(methods, isNot(contains('ensureAgent')));
      expect(killsSent(), hasLength(1));
      manager.dispose();
    });
  });

  test('adopting a server session reuses its name for the new tab', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    backend.remoteSessionList = 'termphin_abc123\t2\t1700000000\t0\n';
    final remote = await manager.listRemoteSessions(profile);
    expect(remote.single.name, 'termphin_abc123');

    final tabId = manager.adoptRemoteSession(profile, remote.single.name);
    final session = await manager.startSession(profile, sessionId: tabId);
    expect(session.muxName, 'termphin_abc123');
    expect(session.multiplexer, Multiplexer.termphin);
    manager.dispose();
  });

  test('remote helper version and SHAs are cached per profile', () async {
    final profile = profileFixture();
    final manager = buildManager();

    remoteAgentService.state = RemoteAgentState.updateAvailable;
    remoteAgentService.remoteSha256 = 'b' * 64;
    final status = await manager.probeAgent(profile);
    expect(status.state, RemoteAgentState.updateAvailable);
    expect(status.bundledSha256, 'a' * 64);
    expect(status.remoteSha256, 'b' * 64);
    expect(manager.agentStatusFor(profile.id), same(status));

    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString('remote_agent_status_${profile.id}');
    expect(stored, contains('"bundledSha256":"${'a' * 64}"'));
    expect(stored, contains('"remoteSha256":"${'b' * 64}"'));
    manager.dispose();

    final restored = buildManager();
    await restored.init();
    expect(restored.agentStatusFor(profile.id)?.updateAvailable, isTrue);

    final updated = await restored.updateAgent(profile);
    expect(updated.state, RemoteAgentState.current);
    expect(restored.agentStatusFor(profile.id)?.updateAvailable, isFalse);
    restored.dispose();
  });

  test('renaming a live session updates the tab and session muxName', () async {
    final profile = profileFixture();
    await ProfileStorageSeed.seed([profile]);
    final manager = buildManager();
    await manager.init();

    await manager.startSession(profile, sessionId: 'tab-1');
    await manager.renameSession('tab-1', 'termphin_renamed');

    expect(
      (backend.calls
              .lastWhere((call) => call.method == 'runWithResult')
              .arguments
          as Map)['command'],
      contains('termphin_renamed'),
    );
    expect(manager.getSession('tab-1')?.muxName, 'termphin_renamed');
    expect(manager.muxNameFor('tab-1'), 'termphin_renamed');
    manager.dispose();
  });

  test(
    'renaming a remote session updates any tab bound to the old name',
    () async {
      final profile = profileFixture();
      await ProfileStorageSeed.seed([profile]);
      final manager = buildManager();
      await manager.init();

      final session = await manager.startSession(profile, sessionId: 'tab-1');
      final oldName = session.muxName!;
      await manager.stopSession('tab-1');

      await manager.renameRemoteSession(profile, oldName, 'termphin_new');

      expect(manager.muxNameFor('tab-1'), 'termphin_new');
      expect(manager.getSession('tab-1')?.muxName, 'termphin_new');
      manager.dispose();
    },
  );

  test('tab records without a backend default to no multiplexer', () {
    final tab = SessionTab.fromJson({
      'tabId': 'legacy-tab',
      'profileId': 'profile-1',
      'muxName': 'termphin_legacy',
      'lastSeen': DateTime.utc(2026).toIso8601String(),
    });
    expect(tab.multiplexer, Multiplexer.none);
  });

  test('tab records survive a JSON round trip', () {
    final tab = SessionTab(
      tabId: 'tab-1',
      profileId: 'profile-1',
      muxName: 'termphin_abc123',
      lastSeen: DateTime.utc(2026, 7, 30, 12, 30),
      detached: true,
    );
    final decoded = SessionTab.fromJson(
      jsonDecode(jsonEncode(tab.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.tabId, tab.tabId);
    expect(decoded.muxName, tab.muxName);
    expect(decoded.detached, isTrue);
    expect(decoded.lastSeen, tab.lastSeen);
    expect(decoded.multiplexer, Multiplexer.termphin);
  });
}

/// Writes profiles straight into the storage key the manager reads when
/// rebuilding offline tabs.
class ProfileStorageSeed {
  static Future<void> seed(List<SshProfile> profiles) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'ssh_profiles',
      SshProfile.encodeList(profiles),
    );
  }
}

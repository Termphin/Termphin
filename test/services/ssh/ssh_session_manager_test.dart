import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/active_session.dart';
import 'package:termphin/models/remote_shell.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../../support/fixtures.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSshBackend backend;
  late FakeRemoteAgentService remoteAgentService;
  late SshSessionManager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    backend = FakeSshBackend();
    remoteAgentService = FakeRemoteAgentService(backend);
    manager = SshSessionManager.test(
      remoteAgentService: remoteAgentService,
      serviceFactory: backend.createService,
    );
  });

  tearDown(() => manager.dispose());

  test('restores offline tabs, order, and last selected session', () async {
    final first = profileFixture(id: 'first-profile');
    final second = profileFixture(id: 'second-profile');
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': SshProfile.encodeList([first, second]),
      'active_session_order': ['second', 'first'],
      'last_active_session_id': 'first',
      'session_tabs': [
        jsonEncode(
          SessionTab(
            tabId: 'first',
            profileId: first.id,
            muxName: 'termphin_first',
            lastSeen: DateTime.utc(2026, 1, 1),
          ).toJson(),
        ),
        jsonEncode(
          SessionTab(
            tabId: 'second',
            profileId: second.id,
            muxName: 'termphin_second',
            lastSeen: DateTime.utc(2026, 1, 2),
          ).toJson(),
        ),
      ],
    });

    await manager.init();

    expect(manager.tabs.map((session) => session.id), ['second', 'first']);
    expect(manager.activeSessions, isEmpty);
    expect(manager.lastSession?.id, 'first');
    expect(manager.getSession('first')?.dropped, isTrue);
  });

  test('a deliberately detached tab is not counted as restorable', () async {
    final profile = profileFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': SshProfile.encodeList([profile]),
      'active_session_order': ['open-one', 'open-two', 'detached'],
      'last_active_session_id': 'open-one',
      'session_tabs': [
        for (final (id, detached) in [
          ('open-one', false),
          ('open-two', false),
          ('detached', true),
        ])
          jsonEncode(
            SessionTab(
              tabId: id,
              profileId: profile.id,
              muxName: 'termphin_$id',
              lastSeen: DateTime.utc(2026, 1, 1),
              detached: detached,
              wasConnected: true,
            ).toJson(),
          ),
      ],
    });

    await manager.init();

    expect(manager.tabs, hasLength(3));
    expect(manager.restorableTabs.map((session) => session.id), [
      'open-one',
      'open-two',
    ]);
    expect(manager.restoreStripSize('open-one'), 2);
  });

  test('the session asked for counts even when nothing restores it', () async {
    final profile = profileFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': SshProfile.encodeList([profile]),
      'session_tabs': [
        jsonEncode(
          SessionTab(
            tabId: 'kept',
            profileId: profile.id,
            muxName: 'termphin_kept',
            lastSeen: DateTime.utc(2026, 1, 1),
            wasConnected: true,
          ).toJson(),
        ),
        jsonEncode(
          SessionTab(
            tabId: 'detached',
            profileId: profile.id,
            muxName: 'termphin_detached',
            lastSeen: DateTime.utc(2026, 1, 1),
            detached: true,
            wasConnected: true,
          ).toJson(),
        ),
      ],
    });

    await manager.init();

    expect(manager.restoreStripSize('detached'), 2);
  });

  test('discards malformed tabs and tabs whose profile is gone', () async {
    SharedPreferences.setMockInitialValues({
      'session_tabs': [
        jsonEncode(
          SessionTab(
            tabId: 'missing-profile',
            profileId: 'missing',
            muxName: 'termphin_missing',
            lastSeen: DateTime.utc(2026),
          ).toJson(),
        ),
        'not-json',
      ],
    });

    await manager.init();

    expect(manager.tabs, isEmpty);
  });

  test('starts, reuses, replays, and disconnects a Dart session', () async {
    final profile = profileFixture();

    final first = await manager.startSession(profile, sessionId: 'session');
    final reused = await manager.startSession(profile, sessionId: 'session');
    backend.latestService.emit([4, 5, 6]);
    await Future<void>.delayed(Duration.zero);
    final replay = await manager.requestReplay('session');

    expect(reused, same(first));
    expect(
      backend.calls.where((call) => call.method == 'connect'),
      hasLength(1),
    );
    expect(replay, [4, 5, 6]);
    expect(first.pendingReplay, [4, 5, 6]);

    await manager.disconnectSession('session');
    expect(manager.hasSession('session'), isFalse);
    expect(backend.calls.map((call) => call.method), contains('disconnect'));
  });

  test(
    'falls back to a plain terminal on a host the agent does not support',
    () async {
      remoteAgentService.supported = false;

      final session = await manager.startSession(
        profileFixture(),
        sessionId: 'session',
      );

      expect(session.multiplexer, Multiplexer.none);
      expect(
        backend.calls.map((call) => call.method),
        isNot(contains('ensureAgent')),
      );
    },
  );

  test('delivers output and marks a closed session as dropped', () async {
    final session = await manager.startSession(
      profileFixture(),
      sessionId: 'events',
    );
    final outputFuture = session.outputStream.first;

    backend.latestService.emit([1, 2]);
    expect((await outputFuture).toList(), [1, 2]);

    backend.latestService.fakeSession.close();
    await Future<void>.delayed(Duration.zero);
    expect(session.dropped, isTrue);
    expect(manager.activeCount, 0);
  });

  test('a session the agent keeps is watched as resumable', () async {
    await manager.startSession(profileFixture(), sessionId: 'kept');

    expect(backend.latestService.healthCheckResumable, isTrue);
  });

  test('measures a round trip once the replay is in', () async {
    await manager.startSession(
      profileFixture(),
      sessionId: 'measured',
      replayRemoteHistory: true,
    );

    expect(backend.latestService.latencyMeasurements, 1);
  });

  test('a plain session keeps the long silence limit', () async {
    remoteAgentService.supported = false;
    await manager.startSession(profileFixture(), sessionId: 'plain');

    expect(backend.latestService.healthCheckResumable, isFalse);
  });

  test('probes only live sessions that survive a reconnect', () async {
    await manager.startSession(profileFixture(), sessionId: 'kept');
    final kept = backend.latestService;
    await manager.startSession(
      profileFixture(id: 'other', host: 'other.example'),
      sessionId: 'gone',
    );
    final gone = backend.latestService;
    manager.markSessionDropped('gone');
    remoteAgentService.supported = false;
    await manager.startSession(
      profileFixture(id: 'third', host: 'third.example'),
      sessionId: 'plain',
    );
    final plain = backend.latestService;

    manager.probeSessions();

    expect(kept.probes, 1);
    expect(kept.lastProbeQuick, isFalse);
    expect(gone.probes, 0);
    expect(plain.probes, 0);
  });

  test('a handover probes quickly', () async {
    await manager.startSession(profileFixture(), sessionId: 'moved');

    manager.probeSessions(handover: true);

    expect(backend.latestService.lastProbeQuick, isTrue);
  });

  group('resuming a dropped session', () {
    const replayEnd = '\x1b]5380;termphin-replay-end\x07';
    const resumeEnd = '\x1b]5380;termphin-resume-end\x07';
    String offset(int n, {int epoch = 5}) =>
        '\x1b]5383;termphin-offset;$epoch:$n\x07';

    setUp(() {
      remoteAgentService.remoteVersion = '0.12.0';
      backend.attachOutput = (command) {
        final resume = RegExp(r'--resume 5:(\d+)').firstMatch(command);
        if (resume == null) {
          return utf8.encode('history$replayEnd${offset(100)}');
        }
        final from = int.parse(resume.group(1)!);
        return utf8.encode('missed$resumeEnd${offset(from + 6)}');
      };
    });

    Future<ActiveSessionView> connected() async {
      final session = await manager.startSession(
        profileFixture(),
        sessionId: 'kept',
        replayRemoteHistory: true,
      );
      await Future<void>.delayed(Duration.zero);
      return session;
    }

    test('knows where its output stands', () async {
      final session = await connected();
      backend.latestService.emit(utf8.encode('abc'));
      await Future<void>.delayed(Duration.zero);

      expect(session.outputPosition, (epoch: '5', offset: 103));
    });

    test('continues on the same session from where it stopped', () async {
      final session = await connected();
      backend.latestService.emit(utf8.encode('abc'));
      await Future<void>.delayed(Duration.zero);
      manager.markSessionDropped('kept');
      final delivered = <String>[];
      session.outputStream.listen((b) => delivered.add(utf8.decode(b)));

      final resumed = await manager.startSession(
        profileFixture(),
        sessionId: 'kept',
        replayRemoteHistory: true,
        resume: true,
      );

      expect(resumed, same(session));
      expect(resumed.resumedInPlace, isTrue);
      expect(resumed.dropped, isFalse);
      final attach = backend.calls.lastWhere((c) => c.method == 'startShell');
      expect((attach.arguments as Map)['command'], contains('--resume 5:103'));
      expect(delivered.join(), startsWith('missed'));
      expect(resumed.outputPosition, (epoch: '5', offset: 109));
      expect(
        utf8.decode(resumed.rawHistorySnapshot),
        allOf(startsWith('history'), contains('abcmissed')),
        reason: 'a terminal mounted later replays all of it',
      );
    });

    test('a session detached on purpose attaches fresh, not onto the '
        'one it closed', () async {
      final detached = await connected();
      await manager.stopSession('kept');

      final attached = await manager.startSession(
        profileFixture(),
        sessionId: 'kept',
        replayRemoteHistory: true,
        resume: true,
      );
      final delivered = <String>[];
      attached.outputStream.listen((b) => delivered.add(utf8.decode(b)));
      backend.latestService.emit(utf8.encode('live'));
      await Future<void>.delayed(Duration.zero);

      expect(attached, isNot(same(detached)));
      final attach = backend.calls.lastWhere((c) => c.method == 'startShell');
      expect((attach.arguments as Map)['command'], isNot(contains('--resume')));
      expect(utf8.decode(attached.pendingReplay!), startsWith('history'));
      expect(delivered.join(), 'live');
    });

    test('a replay instead of a resume starts the history over', () async {
      final session = await connected();
      manager.markSessionDropped('kept');
      backend.attachOutput = (_) =>
          utf8.encode('fresh$replayEnd${offset(900, epoch: 6)}');
      final delivered = <String>[];
      session.outputStream.listen((b) => delivered.add(utf8.decode(b)));

      final resumed = await manager.startSession(
        profileFixture(),
        sessionId: 'kept',
        replayRemoteHistory: true,
        resume: true,
      );

      expect(resumed.resumedInPlace, isFalse);
      expect(
        delivered,
        isEmpty,
        reason: 'the terminal on screen must not take a replay on top',
      );
      expect(utf8.decode(resumed.rawHistorySnapshot), startsWith('fresh'));
      expect(resumed.outputPosition, (epoch: '6', offset: 900));
    });

    test('an agent too old to resume is asked for a replay only', () async {
      await connected();
      manager.markSessionDropped('kept');
      remoteAgentService.remoteVersion = '0.11.0';

      await manager.startSession(
        profileFixture(),
        sessionId: 'kept',
        replayRemoteHistory: true,
        resume: true,
      );

      final attach = backend.calls.lastWhere((c) => c.method == 'startShell');
      expect((attach.arguments as Map)['command'], isNot(contains('--resume')));
    });

    test('an agent that never said where it stands is not resumed', () async {
      backend.attachOutput = null;
      await connected();
      manager.markSessionDropped('kept');

      expect(manager.canResume('kept'), isFalse);
    });

    test('a Windows session is never resumed', () async {
      backend.remoteShellType = RemoteShellType.powershell;
      await connected();
      manager.markSessionDropped('kept');

      expect(manager.canResume('kept'), isFalse);
    });

    test('a failed resume leaves it resumable from the same place', () async {
      final session = await connected();
      manager.markSessionDropped('kept');
      backend.connectError = Exception('refused');

      await expectLater(
        manager.startSession(
          profileFixture(),
          sessionId: 'kept',
          replayRemoteHistory: true,
          resume: true,
        ),
        throwsException,
      );

      expect(manager.getSession('kept'), same(session));
      expect(manager.canResume('kept'), isTrue);
      expect(session.outputPosition, (epoch: '5', offset: 100));
    });

    test('the old transport can no longer drop the resumed one', () async {
      await connected();
      final old = backend.latestService;
      manager.markSessionDropped('kept');
      await manager.startSession(
        profileFixture(),
        sessionId: 'kept',
        replayRemoteHistory: true,
        resume: true,
      );

      old.onConnectionLost?.call();

      expect(manager.getSession('kept')!.dropped, isFalse);
    });
  });

  test('sends write, resize, exec, and tunnel commands', () async {
    await manager.startSession(profileFixture(), sessionId: 'session');

    manager.sendInput('session', Uint8List.fromList([1]));
    manager.resize('session', 100, 30);
    expect((await manager.exec('session', 'uname')).toList(), [7, 8]);
    await manager.openTunnel('session', 'rule', 'local', 8080, 'localhost', 80);
    await manager.closeTunnel('session', 'rule', 'local');

    expect(
      backend.calls.map((call) => call.method),
      containsAll(['write', 'resize', 'exec', 'tunnelOpen', 'tunnelClose']),
    );
  });

  test('numbers input and reports the server receiving it', () async {
    final session = await manager.startSession(
      profileFixture(),
      sessionId: 'session',
    );
    final inputs = <int>[];
    final receipts = <int>[];
    session.inputStream.listen((input) => inputs.add(input.seq));
    session.inputReceipts.listen(receipts.add);
    final service = backend.latestService;

    manager.sendInput('session', Uint8List.fromList([0x61]));
    manager.sendInput('session', Uint8List.fromList([0x62]));
    manager.sendInput('session', Uint8List.fromList([0x63]));
    expect(service.receipts, hasLength(1));

    service.receipts.first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(receipts, [1]);
    expect(service.receipts, hasLength(2));

    service.receipts.last.complete();
    await Future<void>.delayed(Duration.zero);
    expect(inputs, [1, 2, 3]);
    expect(receipts, [1, 3]);
  });

  test('asks for no receipts with predictive echo off', () async {
    await terminalSettings.predictiveEcho.set(false);
    addTearDown(() => terminalSettings.predictiveEcho.set(true));
    await manager.startSession(profileFixture(), sessionId: 'session');

    manager.sendInput('session', Uint8List.fromList([0x61]));

    expect(backend.latestService.receipts, isEmpty);
  });

  test('never tells the server the terminal has no rows', () async {
    await manager.startSession(profileFixture(), sessionId: 'session');

    manager.resize('session', 100, 0);
    manager.resize('session', 0, -3);

    final resizes = backend.calls
        .where((call) => call.method == 'resize')
        .map((call) => call.arguments! as Map)
        .toList();
    expect(resizes.map((args) => args['height']), everyElement(greaterThan(0)));
    expect(resizes.map((args) => args['width']), everyElement(greaterThan(0)));
    expect(resizes.last, {'width': 1, 'height': 1});
  });

  test('splits are saved, and a restore hands back only whole ones', () async {
    final profile = profileFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': SshProfile.encodeList([profile]),
      'session_splits': [
        jsonEncode({'first': 'one', 'second': 'two', 'ratio': 0.3}),
        jsonEncode({'first': 'three', 'second': 'gone', 'ratio': 0.5}),
      ],
      'session_tabs': [
        for (final id in ['one', 'two', 'three'])
          jsonEncode(
            SessionTab(
              tabId: id,
              profileId: profile.id,
              muxName: 'termphin_$id',
              lastSeen: DateTime.utc(2026, 1, 1),
              wasConnected: true,
            ).toJson(),
          ),
      ],
    });

    await manager.init();

    expect(manager.savedSplits, [(first: 'one', second: 'two', ratio: 0.3)]);
    await pumpEventQueue();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('session_splits'), hasLength(1));
  });

  test('a strip saving its splits rewrites only the tabs it holds', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await manager.startSession(profileFixture(), sessionId: id);
    }
    manager.saveSplits(['a', 'b'], [(first: 'a', second: 'b', ratio: 0.5)]);
    manager.saveSplits(['c', 'd'], [(first: 'd', second: 'c', ratio: 0.4)]);
    manager.saveSplits(['a', 'b'], const []);
    await pumpEventQueue();

    expect(manager.savedSplits, [(first: 'd', second: 'c', ratio: 0.4)]);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences
          .getStringList('session_splits')!
          .map((raw) => jsonDecode(raw))
          .toList(),
      [
        {'first': 'd', 'second': 'c', 'ratio': 0.4},
      ],
    );
  });

  test('persists session ordering and the last active session', () async {
    await manager.startSession(profileFixture(), sessionId: 'first');
    await manager.startSession(profileFixture(), sessionId: 'second');

    manager.reorderSessions(['second', 'first']);
    await manager.setActiveSession('first');
    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getStringList('active_session_order'), [
      'second',
      'first',
    ]);
    expect(preferences.getString('last_active_session_id'), 'first');
    expect(manager.getSession('first')?.remoteShellType, RemoteShellType.unix);
  });

  test('re-attaching the same host does not probe the agent again', () async {
    final profile = profileFixture();

    await manager.startSession(profile, sessionId: 'first');
    expect(
      backend.calls.map((call) => call.method),
      contains('probeAgent'),
      reason: 'the first attach has nothing cached to go on',
    );

    await manager.disconnectSession('first');
    backend.calls.clear();
    await manager.startSession(profile, sessionId: 'second');

    expect(
      backend.calls.map((call) => call.method),
      isNot(contains('probeAgent')),
    );
    expect(
      manager.getSession('second')?.multiplexer,
      Multiplexer.termphin,
      reason: 'skipping the probe must not cost the session its persistence',
    );
  });

  test('a cached probe does not answer for a different host', () async {
    await manager.startSession(profileFixture(id: 'one'), sessionId: 'first');
    backend.calls.clear();

    await manager.startSession(profileFixture(id: 'two'), sessionId: 'second');

    expect(backend.calls.map((call) => call.method), contains('probeAgent'));
  });

  test('listing server sessions runs over a live transport', () async {
    final profile = profileFixture();
    backend.remoteSessionList = 'termphin_abc123\t2\t1700000000\t0\n';
    await manager.startSession(profile, sessionId: 'tab-1');
    final connectsBefore = backend.calls
        .where((call) => call.method == 'connect')
        .length;

    final sessions = await manager.listRemoteSessions(profile);

    expect(sessions, hasLength(1));
    expect(
      backend.calls.where((call) => call.method == 'connect'),
      hasLength(connectsBefore),
    );
  });

  test('listing server sessions connects when nothing is live', () async {
    final profile = profileFixture();
    backend.remoteSessionList = 'termphin_abc123\t2\t1700000000\t0\n';

    final sessions = await manager.listRemoteSessions(profile);

    expect(sessions, hasLength(1));
    expect(
      backend.calls.where((call) => call.method == 'connect'),
      hasLength(1),
    );
  });

  test('a session stays connecting until its shell is attached', () async {
    final profile = profileFixture();
    backend.connectGate = Completer<void>();
    final started = manager.startSession(profile, sessionId: 'pending-1');
    await backend.connectCalled.future;

    expect(manager.getSession('pending-1')!.connecting, isTrue);

    backend.connectGate!.complete();
    await started;

    expect(manager.getSession('pending-1')!.connecting, isFalse);
  });

  test('coming back to the app leaves a connect in flight alone', () async {
    final profile = profileFixture();
    backend.connectGate = Completer<void>();
    final started = manager.startSession(profile, sessionId: 'pending-3');
    await backend.connectCalled.future;

    manager.dropDeadSessions();

    expect(manager.getSession('pending-3')!.dropped, isFalse);
    expect(manager.getSession('pending-3')!.connecting, isTrue);

    backend.connectGate!.complete();
    await started;
    expect(manager.getSession('pending-3')!.dropped, isFalse);
  });

  test(
    'a connect that drops mid-handshake stops reading as connecting',
    () async {
      final profile = profileFixture();
      backend.connectGate = Completer<void>();
      final started = manager.startSession(profile, sessionId: 'pending-2');
      await backend.connectCalled.future;

      manager.markSessionDropped('pending-2');

      expect(manager.getSession('pending-2')!.connecting, isFalse);

      backend.connectGate!.complete();
      await started;
    },
  );

  test(
    'cancelling a connect before it attaches leaves nothing behind',
    () async {
      final profile = profileFixture();
      backend.connectGate = Completer<void>();
      final started = manager.startSession(profile, sessionId: 'cancelled-1');
      await backend.connectCalled.future;

      await manager.stopSession('cancelled-1');

      expect(manager.sessions, isEmpty);
      expect(manager.restorableTabs, isEmpty);
      expect(manager.restoreStripSize('anything-else'), 1);

      backend.connectGate!.complete();
      await started;
    },
  );

  group('stripHoldsTab', () {
    test('holds a tab that is connected', () async {
      await manager.startSession(profileFixture(), sessionId: 'session');

      expect(manager.stripHoldsTab('session'), isTrue);
    });

    test('drops a tab once it is detached', () async {
      await manager.startSession(profileFixture(), sessionId: 'session');

      await manager.stopSession('session');

      expect(manager.stripHoldsTab('session'), isFalse);
    });

    test('drops a tab once its session is ended', () async {
      await manager.startSession(profileFixture(), sessionId: 'session');

      await manager.endSession('session');

      expect(manager.stripHoldsTab('session'), isFalse);
    });

    test('drops a tab that was forgotten outright', () async {
      await manager.startSession(profileFixture(), sessionId: 'session');

      await manager.forgetTab('session');

      expect(manager.stripHoldsTab('session'), isFalse);
    });

    test('keeps a tab that merely lost its connection', () async {
      await manager.startSession(profileFixture(), sessionId: 'session');

      manager.markSessionDropped('session');

      expect(manager.stripHoldsTab('session'), isTrue);
      expect(
        manager.restorableTabs.map((session) => session.id),
        isNot(contains('session')),
      );
    });

    test('does not hold a tab it has never heard of', () {
      expect(manager.stripHoldsTab('never-opened'), isFalse);
    });
  });

  group('closing a tab whose disconnect throws', () {
    test('still drops the tab and notifies listeners', () async {
      await manager.startSession(profileFixture(), sessionId: 'session');
      backend.latestService.fakeSession.closeError = Exception('boom');
      var notified = 0;
      manager.addListener(() => notified++);

      await expectLater(manager.stopSession('session'), throwsException);

      expect(manager.stripHoldsTab('session'), isFalse);
      expect(notified, greaterThan(0));
    });
  });
}

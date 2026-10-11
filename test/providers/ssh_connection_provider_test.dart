import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/remote_agent_status.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/network_monitor_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/ssh/keepalive_pinger.dart';
import 'package:termphin/services/ssh/network_monitor.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/ssh_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const analyticsChannel = MethodChannel('posthog_flutter');
  final capturedEvents = <String>[];
  final capturedProperties = <String, Map<String, Object?>>{};

  late FakeSshBackend backend;
  late FakeRemoteAgentService remoteAgentService;
  late SshSessionManager manager;
  late FakeProfileStorage profileStorage;
  late StreamController<bool> networkChanges;
  late NetworkMonitor network;
  late bool probeOnline;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    capturedEvents.clear();
    capturedProperties.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async {
          if (call.method == 'capture') {
            final arguments = call.arguments as Map;
            final event = arguments['eventName'] as String;
            capturedEvents.add(event);
            capturedProperties[event] = Map<String, Object?>.from(
              (arguments['properties'] as Map?) ?? const {},
            );
          }
          return null;
        });
    AnalyticsService.instance.resetForTest();
    await AnalyticsService.instance.setConsent(true);
    capturedEvents.clear();
    capturedProperties.clear();
    backend = FakeSshBackend();
    remoteAgentService = FakeRemoteAgentService(backend);
    manager = SshSessionManager.test(
      remoteAgentService: remoteAgentService,
      serviceFactory: backend.createService,
    );
    profileStorage = FakeProfileStorage([profileFixture()]);
    networkChanges = StreamController<bool>.broadcast();
    probeOnline = true;
    List<ConnectivityResult> reading(bool online) => [
      online ? ConnectivityResult.wifi : ConnectivityResult.none,
    ];
    network = NetworkMonitor(
      changes: networkChanges.stream.map(reading),
      probe: () async => reading(probeOnline),
    );
    await network.init();
  });

  tearDown(() async {
    manager.dispose();
    await network.dispose();
    await networkChanges.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
  });

  ProviderContainer createContainer() => ProviderContainer.test(
    overrides: [
      sshSessionManagerProvider.overrideWithValue(manager),
      profileStorageProvider.overrideWithValue(profileStorage),
      networkMonitorProvider.overrideWithValue(network),
    ],
  );

  /// Drives the monitor the way the platform would, and waits for it to have
  /// seen the change before the test acts on it.
  Future<void> setOnline(bool online) async {
    networkChanges.add(online);
    await pumpEventQueue();
  }

  test(
    'starts disconnected and connects with requested PTY dimensions',
    () async {
      final container = createContainer();
      final key = ('session-1', profileFixture());
      final provider = sshConnectionProvider(key);

      expect(container.read(provider).status, ConnectionStatus.disconnected);

      await container
          .read(provider.notifier)
          .connect(initialWidth: 120, initialHeight: 40);

      final state = container.read(provider);
      final shellCall = backend.calls.firstWhere(
        (call) => call.method == 'startShell',
      );
      expect(state.status, ConnectionStatus.connected);
      expect(state.errorMessage, isNull);
      expect(shellCall.arguments, containsPair('width', 120));
      expect(shellCall.arguments, containsPair('height', 40));
      expect(
        (shellCall.arguments as Map)['command'],
        contains('attach --replay'),
      );
      expect(manager.getSession('session-1')?.pendingReplay, isNotEmpty);
      expect(capturedEvents, contains('connection_success'));
      expect(capturedEvents, isNot(contains('session_resumed')));
    },
  );

  test(
    'reattaching a detached tab dials the host the machine has now',
    () async {
      final container = createContainer();
      final original = profileFixture();
      final provider = sshConnectionProvider(('detached', original));
      await container.read(provider.notifier).connect();
      await container.read(provider.notifier).disconnect();

      final profiles = container.read(profilesProvider.notifier);
      await profiles.loadProfiles();
      await profiles.updateProfile(
        original,
        name: original.name,
        host: 'new.example.com',
        port: original.port,
        username: original.username,
        authMethod: original.authMethod,
        password: original.password,
      );
      await container.read(provider.notifier).connect();

      final hosts = [
        for (final call in backend.calls)
          if (call.method == 'connect') (call.arguments as Map)['host'],
      ];
      expect(hosts.last, 'new.example.com');
      expect(manager.getSession('detached')?.profile.host, 'new.example.com');
    },
  );

  test('replays remote history again after an in-place reconnect', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('reconnect', profileFixture()));
    final notifier = container.read(provider.notifier);
    await notifier.connect();
    backend.calls.clear();

    await notifier.reconnect();

    final shellCall = backend.calls.firstWhere(
      (call) => call.method == 'startShell',
    );
    expect(
      (shellCall.arguments as Map)['command'],
      contains('attach --replay'),
    );
  });

  test('shows every server message while connect is pending', () async {
    final container = createContainer();
    final key = ('session-log', profileFixture());
    final provider = sshConnectionProvider(key);
    backend.connectGate = Completer<void>();
    backend.connectionMessages = ['Visit https://example.com/auth'];

    final connectFuture = container.read(provider.notifier).connect();
    await backend.connectCalled.future;

    expect(container.read(provider).connectionLog, [
      'Connecting to example.com:22',
      'Visit https://example.com/auth',
    ]);

    backend.connectGate!.complete();
    await connectFuture;
  });

  test('moves to error and records the failure when connect fails', () async {
    final container = createContainer();
    final key = ('session-error', profileFixture());
    final provider = sshConnectionProvider(key);
    backend.connectError = Exception('Host unreachable');

    await container.read(provider.notifier).connect();

    final state = container.read(provider);
    expect(state.status, ConnectionStatus.error);
    expect(state.errorMessage, contains('Host unreachable'));
    expect(state.connectionLog.last, contains('Host unreachable'));
    expect(manager.hasSession('session-error'), isFalse);
  });

  test('the failure reason reaches the state, not just analytics', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('reasoned', profileFixture()));
    backend.connectError = const SshConnectException(
      SshFailureReason.keyPassphrase,
      'The key could not be unlocked. Check its passphrase.',
    );

    await container.read(provider.notifier).connect();

    expect(
      container.read(provider).failureReason,
      SshFailureReason.keyPassphrase,
    );
  });

  test('an unclassified failure carries unknown rather than null', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('opaque-state', profileFixture()));
    backend.connectError = Exception('something went sideways');

    await container.read(provider.notifier).connect();

    expect(container.read(provider).failureReason, SshFailureReason.unknown);
  });

  test('a retry after a failure clears the reason with the message', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('cleared', profileFixture()));
    backend.connectError = const SshConnectException(
      SshFailureReason.keyInvalid,
      'The key could not be read.',
    );

    await container.read(provider.notifier).connect();
    expect(container.read(provider).failureReason, SshFailureReason.keyInvalid);

    backend.connectError = null;
    await container.read(provider.notifier).connect();

    final state = container.read(provider);
    expect(state.status, ConnectionStatus.connected);
    expect(state.errorMessage, isNull);
    expect(state.failureReason, isNull);
  });

  test('attaches to an existing session without connecting again', () async {
    final profile = profileFixture();
    await manager.startSession(profile, sessionId: 'existing');
    backend.latestService.emit([1, 2, 3]);
    await Future<void>.delayed(Duration.zero);
    backend.calls.clear();
    final container = createContainer();
    final provider = sshConnectionProvider(('existing', profile));

    await container.read(provider.notifier).connect();

    expect(container.read(provider).status, ConnectionStatus.connected);
    expect(backend.calls.where((call) => call.method == 'connect'), isEmpty);
    expect(manager.getSession('existing')?.pendingReplay, [1, 2, 3]);
    expect(capturedEvents, contains('session_resumed'));
    expect(capturedEvents, isNot(contains('connection_success')));
  });

  test('a reconnect opens the shell at the size the view last sent', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('resized', profileFixture()));
    final notifier = container.read(provider.notifier);
    await notifier.connect(initialWidth: 80, initialHeight: 24);

    notifier.resize(100, 40);
    await notifier.reconnect();

    final shells = backend.calls.where((call) => call.method == 'startShell');
    expect(shells.last.arguments, containsPair('width', 100));
    expect(shells.last.arguments, containsPair('height', 40));
  });

  test('reconnects a persistent session after its transport drops', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('dropped', profileFixture()));
    await container.read(provider.notifier).connect();

    manager.markSessionDropped('dropped');

    expect(container.read(provider).status, ConnectionStatus.reconnecting);
    expect(container.read(provider).reconnectAttempt, 1);
    expect(container.read(provider).errorMessage, isNull);
  });

  test('a drop with no network parks instead of spending an attempt', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('offline', profileFixture()));
    await container.read(provider.notifier).connect();
    await setOnline(false);

    manager.markSessionDropped('offline');

    final state = container.read(provider);
    expect(state.status, ConnectionStatus.reconnecting);
    expect(state.waitingForNetwork, isTrue);
    expect(
      state.reconnectAttempt,
      0,
      reason: 'a radio that is off has not refused anything worth counting',
    );
    expect(state.reconnectSecondsRemaining, 0);
  });

  test('a parked session reconnects the moment the network is back', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('regain', profileFixture()));
    await container.read(provider.notifier).connect();
    await setOnline(false);
    manager.markSessionDropped('regain');
    expect(container.read(provider).waitingForNetwork, isTrue);

    await setOnline(true);

    final state = container.read(provider);
    expect(state.status, ConnectionStatus.connected);
    expect(state.waitingForNetwork, isFalse);
  });

  test('a parked session re-reads a network nothing announced', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider((
        'missed-event',
        profileFixture(),
      ));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();
      expect(container.read(provider).status, ConnectionStatus.connected);

      probeOnline = false;
      networkChanges.add(false);
      async.flushMicrotasks();
      manager.markSessionDropped('missed-event');
      async.flushMicrotasks();
      expect(container.read(provider).waitingForNetwork, isTrue);

      probeOnline = true;
      async.elapse(const Duration(seconds: 25));
      async.flushMicrotasks();

      final state = container.read(provider);
      expect(state.waitingForNetwork, isFalse);
      expect(state.status, ConnectionStatus.connected);
    });
  });

  test('the first retry after a drop does not wait', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider(('prompt', profileFixture()));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();

      manager.markSessionDropped('prompt');
      async.elapse(const Duration(milliseconds: 100));

      expect(container.read(provider).status, ConnectionStatus.connected);
    });
  });

  test('a failed first retry counts down to the next', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider(('refused', profileFixture()));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();

      backend.connectError = Exception('refused');
      manager.markSessionDropped('refused');
      async.elapse(const Duration(milliseconds: 100));

      final state = container.read(provider);
      expect(state.status, ConnectionStatus.reconnecting);
      expect(state.reconnectAttempt, 2);
      expect(state.reconnectSecondsRemaining, greaterThan(0));
    });
  });

  test('keeps retrying a server that stays unreachable', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider(('patient', profileFixture()));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();

      backend.connectError = const SshConnectException(
        SshFailureReason.hostUnreachable,
        'unreachable',
      );
      manager.markSessionDropped('patient');
      async.elapse(const Duration(minutes: 5));

      final state = container.read(provider);
      expect(state.status, ConnectionStatus.reconnecting);
      expect(state.reconnectAttempt, greaterThan(10));

      backend.connectError = null;
      async.elapse(const Duration(seconds: 31));
      expect(container.read(provider).status, ConnectionStatus.connected);
    });
  });

  test('backs off between retries, up to a ceiling', () {
    expect(
      [
        for (var attempt = 1; attempt <= 8; attempt++)
          SshConnectionNotifier.reconnectDelay(attempt).inSeconds,
      ],
      [0, 1, 2, 4, 8, 16, 30, 30],
    );
  });

  test('a refused login stops retrying at once', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider(('denied', profileFixture()));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();

      backend.connectError = const SshConnectException(
        SshFailureReason.authFailed,
        'denied',
      );
      manager.markSessionDropped('denied');
      async.elapse(const Duration(seconds: 1));

      final state = container.read(provider);
      expect(state.status, ConnectionStatus.error);
      expect(state.failureReason, SshFailureReason.authFailed);
      expect(
        backend.calls.where((call) => call.method == 'connect'),
        hasLength(2),
        reason: 'the password will not be right the second time either',
      );
    });
  });

  test('a drop reports how it was noticed', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('noticed', profileFixture()));
    await container.read(provider.notifier).connect();

    backend.latestService.linkLoss = LinkLoss.probe;
    manager.markSessionDropped('noticed');
    await pumpEventQueue();

    expect(capturedProperties['connection_dropped']?['lost_via'], 'probe');
  });

  test('a drop nobody measured is put down to the transport', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('closed', profileFixture()));
    await container.read(provider.notifier).connect();

    manager.markSessionDropped('closed');
    await pumpEventQueue();

    expect(capturedProperties['connection_dropped']?['lost_via'], 'transport');
  });

  test('a session back after a drop reports how long it was down', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider(('downtime', profileFixture()));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();
      expect(
        capturedProperties['connection_success'],
        isNot(contains('downtime_ms')),
        reason: 'a first connect was never down',
      );

      backend.connectError = Exception('refused');
      manager.markSessionDropped('downtime');
      async.elapse(const Duration(milliseconds: 100));
      backend.connectError = null;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(container.read(provider).status, ConnectionStatus.connected);
      expect(
        capturedProperties['connection_success']?['downtime_ms'],
        greaterThanOrEqualTo(1000),
      );
    });
  });

  group('typing while reconnecting', () {
    List<String> written() => [
      for (final call in backend.calls.where((c) => c.method == 'write'))
        utf8.decode((call.arguments as Map)['data'] as List<int>),
    ];

    test('is held, then sent once asked to after the reconnect', () {
      fakeAsync((async) {
        final container = createContainer();
        final provider = sshConnectionProvider(('typed', profileFixture()));
        final notifier = container.read(provider.notifier);
        notifier.connect();
        async.flushMicrotasks();

        backend.connectError = Exception('refused');
        manager.markSessionDropped('typed');
        async.elapse(const Duration(milliseconds: 100));
        expect(notifier.queueInput(utf8.encode('ls')), isTrue);
        expect(notifier.queueInput([0x0d]), isFalse);

        expect(written(), isEmpty);
        expect(container.read(provider).queuedInput, 2);

        backend.connectError = null;
        async.elapse(const Duration(seconds: 2));
        expect(container.read(provider).status, ConnectionStatus.connected);
        expect(
          written(),
          isEmpty,
          reason: 'held until the new terminal is there to show the echo',
        );

        notifier.flushQueuedInput();

        expect(written(), ['ls']);
        expect(container.read(provider).queuedInput, 0);
      });
    });

    test('is dropped when the session cannot come back', () {
      fakeAsync((async) {
        final container = createContainer();
        final provider = sshConnectionProvider(('lost', profileFixture()));
        final notifier = container.read(provider.notifier);
        notifier.connect();
        async.flushMicrotasks();

        backend.connectError = Exception('refused');
        manager.markSessionDropped('lost');
        async.elapse(const Duration(milliseconds: 100));
        notifier.queueInput(utf8.encode('pwd'));
        backend.connectError = const SshConnectException(
          SshFailureReason.authFailed,
          'denied',
        );
        async.elapse(const Duration(seconds: 2));

        expect(container.read(provider).status, ConnectionStatus.error);
        expect(container.read(provider).queuedInput, 0);
        notifier.flushQueuedInput();
        expect(written(), isEmpty);
      });
    });

    test('is not held on a live session', () async {
      final container = createContainer();
      final provider = sshConnectionProvider(('live', profileFixture()));
      final notifier = container.read(provider.notifier);
      await notifier.connect();

      expect(notifier.queueInput(utf8.encode('x')), isFalse);
    });
  });

  test('a retry runs to a live session, and the next drop retries again', () {
    fakeAsync((async) {
      final container = createContainer();
      final provider = sshConnectionProvider(('cycle', profileFixture()));
      container.read(provider.notifier).connect();
      async.flushMicrotasks();
      expect(container.read(provider).status, ConnectionStatus.connected);

      manager.markSessionDropped('cycle');
      async.flushMicrotasks();
      expect(container.read(provider).status, ConnectionStatus.reconnecting);
      expect(container.read(provider).reconnectAttempt, 1);

      async.elapse(const Duration(seconds: 8));
      async.flushMicrotasks();

      expect(container.read(provider).status, ConnectionStatus.connected);
      expect(container.read(provider).reconnectAttempt, 0);
      expect(container.read(provider).errorMessage, isNull);

      manager.markSessionDropped('cycle');
      async.flushMicrotasks();

      expect(container.read(provider).status, ConnectionStatus.reconnecting);
      expect(container.read(provider).reconnectAttempt, 1);
    });
  });

  test('a network already up does not restart a healthy session', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('healthy', profileFixture()));
    await container.read(provider.notifier).connect();
    backend.calls.clear();

    await setOnline(true);

    expect(container.read(provider).status, ConnectionStatus.connected);
    expect(
      backend.calls.map((call) => call.method),
      isNot(contains('connect')),
    );
  });

  test('disconnect detaches the persistent session and clears state', () async {
    final container = createContainer();
    final provider = sshConnectionProvider(('disconnect', profileFixture()));
    final notifier = container.read(provider.notifier);
    await notifier.connect();

    await notifier.disconnect();

    expect(container.read(provider).status, ConnectionStatus.disconnected);
    expect(manager.hasSession('disconnect'), isTrue);
    expect(manager.getSession('disconnect')?.dropped, isTrue);
    expect(manager.activeSessions, isEmpty);
    expect(backend.calls.map((call) => call.method), contains('disconnect'));
  });

  test(
    'disconnect still clears state when the session fails to close',
    () async {
      final container = createContainer();
      final provider = sshConnectionProvider((
        'disconnect-throws',
        profileFixture(),
      ));
      final notifier = container.read(provider.notifier);
      await notifier.connect();
      backend.latestService.fakeSession.closeError = Exception('boom');

      await expectLater(notifier.disconnect(), throwsException);

      expect(container.read(provider).status, ConnectionStatus.disconnected);
    },
  );

  group('closed through another notifier', () {
    test('a detach does not bring the session back', () async {
      final container = createContainer();
      final own = sshConnectionProvider(('elsewhere', profileFixture()));
      final other = sshConnectionProvider(('elsewhere', profileFixture()));
      await container.read(own.notifier).connect();
      final connects = backend.calls.where((c) => c.method == 'connect');
      final before = connects.length;

      await container.read(other.notifier).disconnect();
      await pumpEventQueue();

      expect(container.read(own).status, ConnectionStatus.disconnected);
      expect(manager.getSession('elsewhere')?.dropped, isTrue);
      expect(connects.length, before);
    });

    test('an end does not bring the session back', () async {
      final container = createContainer();
      final own = sshConnectionProvider(('ended', profileFixture()));
      final other = sshConnectionProvider(('ended', profileFixture()));
      await container.read(own.notifier).connect();
      final connects = backend.calls.where((c) => c.method == 'connect');
      final before = connects.length;

      await container.read(other.notifier).endSession();
      await pumpEventQueue();

      expect(container.read(own).status, ConnectionStatus.disconnected);
      expect(manager.hasSession('ended'), isFalse);
      expect(connects.length, before);
    });
  });

  test('copyWith clears errors and connection logs explicitly', () {
    const state = SshConnectionState(
      status: ConnectionStatus.error,
      errorMessage: 'error',
      connectionLog: ['line'],
      reconnectAttempt: 2,
    );

    final cleared = state.copyWith(
      status: ConnectionStatus.connecting,
      clearError: true,
      clearConnectionLog: true,
    );

    expect(cleared.status, ConnectionStatus.connecting);
    expect(cleared.errorMessage, isNull);
    expect(cleared.connectionLog, isEmpty);
    expect(cleared.reconnectAttempt, 2);
  });

  group('analytics', () {
    test('a classified failure reports its reason, not a guess', () async {
      final container = createContainer();
      final provider = sshConnectionProvider(('failed', profileFixture()));
      backend.connectError = const SshConnectException(
        SshFailureReason.authFailed,
        'Authentication failed. Check your credentials.',
      );

      await container.read(provider.notifier).connect();
      await pumpEventQueue();

      expect(capturedEvents, contains('connection_failed'));
      final shape = capturedProperties['connection_failed']!;
      expect(shape.remove('duration_ms'), isA<int>());
      expect(shape, {
        'auth_method': 'password',
        'via_jump_host': false,
        'fallback_count': 0,
        'port_forwards': 0,
        'reason': 'auth_failed',
        'retry': false,
      });
    });

    test(
      'an unclassified failure reports unknown rather than inventing one',
      () async {
        final container = createContainer();
        final provider = sshConnectionProvider(('opaque', profileFixture()));
        backend.connectError = Exception('something went sideways');

        await container.read(provider.notifier).connect();
        await pumpEventQueue();

        expect(capturedProperties['connection_failed']?['reason'], 'unknown');
      },
    );

    test('a successful connection reports its shape', () async {
      final profile = profileFixture(
        authMethod: AuthMethod.privateKey,
        privateKey: 'pem',
        fallbackHosts: const ['lan.example', 'tailscale.example'],
        portForwardings: [forwardingRuleFixture()],
      );
      profileStorage = FakeProfileStorage([profile]);
      final container = createContainer();
      final provider = sshConnectionProvider(('shaped', profile));

      await container.read(provider.notifier).connect();
      await pumpEventQueue();

      final shape = capturedProperties['connection_success']!;
      expect(shape.remove('duration_ms'), isA<int>());
      expect(shape, {
        'auth_method': 'privateKey',
        'via_jump_host': false,
        'fallback_count': 2,
        'port_forwards': 1,
        'multiplexer': container.read(provider).multiplexer.name,
        'agent_installed': false,
        'used_fallback': false,
      });
    });

    test('a connect that had to upload the agent says so', () async {
      remoteAgentService.state = RemoteAgentState.missing;
      final container = createContainer();
      final provider = sshConnectionProvider(('installing', profileFixture()));

      await container.read(provider.notifier).connect();
      await pumpEventQueue();

      expect(
        capturedProperties['connection_success']?['agent_installed'],
        true,
      );
    });

    test('a jump host profile says so without naming the bastion', () async {
      final profile = profileFixture(jumpHostProfileId: 'bastion-1');
      profileStorage = FakeProfileStorage([profile]);
      final container = createContainer();
      final provider = sshConnectionProvider(('jumped', profile));

      await container.read(provider.notifier).connect();
      await pumpEventQueue();

      expect(capturedProperties['connection_success']?['via_jump_host'], true);
    });

    test('a transport that dies mid-session reports a drop', () async {
      final container = createContainer();
      final provider = sshConnectionProvider(('lost', profileFixture()));
      await container.read(provider.notifier).connect();
      capturedEvents.clear();

      manager.markSessionDropped('lost');
      await pumpEventQueue();

      expect(capturedEvents, contains('connection_dropped'));
      expect(
        capturedProperties['connection_dropped']?['auth_method'],
        'password',
      );
    });

    test(
      'no connection event carries an address, a port or an account',
      () async {
        final profile = profileFixture(
          host: 'secret.example.com',
          username: 'root',
          fallbackHosts: const ['10.0.0.9'],
        );
        final container = createContainer();
        final provider = sshConnectionProvider(('private', profile));
        await container.read(provider.notifier).connect();
        backend.connectError = Exception('nope');
        await container
            .read(sshConnectionProvider(('private-2', profile)).notifier)
            .connect();
        await pumpEventQueue();

        final leaked = [
          profile.host,
          profile.username,
          profile.name,
          '${profile.port}',
          ...profile.fallbackHosts,
        ];
        for (final properties in capturedProperties.values) {
          for (final value in properties.values) {
            expect(leaked, isNot(contains('$value')));
          }
        }
      },
    );
  });
}

@Tags(['security'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/known_host.dart';
import 'package:termphin/providers/network_monitor_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/ssh/network_monitor.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';

import '../support/fake_master_key_store.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/ssh_fakes.dart';

/// A host key that does not check out is never let through, on any path.
///
/// The check itself (`verifyHostKey`) has unit tests of its own. What this
/// pins is that nothing gets around it: one place builds an SSH client and it
/// always asks, a background connection with nobody to ask refuses, a declined
/// or changed key pins nothing, and a refusal is final - a reconnect loop
/// that retried it would re-ask until someone tapped yes.
class _FakeSocket implements SSHSocket {
  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void destroy() {}
}

Uint8List _fingerprint(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the one way in', () {
    final sources = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          (entity.path, entity.readAsStringSync()),
    ];

    test('only SshService builds an SSH client', () {
      final builders = [
        for (final (path, source) in sources)
          if (source.contains('SSHClient(')) path,
      ];
      expect(builders, ['lib/services/ssh/ssh_service.dart']);
      final (_, service) = sources.firstWhere(
        (entry) => entry.$1 == 'lib/services/ssh/ssh_service.dart',
      );
      expect('SSHClient('.allMatches(service), hasLength(1));
    });

    test('that client always routes its host key through verifyHostKey', () {
      final (_, service) = sources.firstWhere(
        (entry) => entry.$1 == 'lib/services/ssh/ssh_service.dart',
      );
      final construction = service.substring(service.indexOf('SSHClient('));
      final call = construction.substring(0, construction.indexOf(');'));
      expect(
        call,
        matches(
          RegExp(
            r'onVerifyHostKey:\s*\(type, fingerprint\)\s*=>\s*'
            r'verifyHostKey\(',
          ),
        ),
      );
    });

    test('nothing answers a host key prompt until the UI is wired', () {
      expect(SshSessionManager.test().hostKeyPrompt, isNull);
    });
  });

  group('a key that does not match', () {
    late KnownHostsStore knownHosts;
    late SshService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      knownHosts = KnownHostsStore(cipher: cipherFixture());
      service = SshService(
        socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
        knownHosts: knownHosts,
      );
      await service.connectSocket(profileFixture());
      await knownHosts.trust(
        KnownHost(
          host: 'example.com',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:pinned',
          addedAt: DateTime(2026),
        ),
      );
    });

    Future<String?> pinned() async => (await knownHosts.lookup(
      'example.com',
      22,
      'ssh-ed25519',
    ))?.fingerprint;

    test('is refused on a background connection, and the pin kept', () async {
      final accepted = await service.verifyHostKey(
        'ssh-ed25519',
        _fingerprint('SHA256:attacker'),
        null,
      );

      expect(accepted, isFalse);
      expect(await pinned(), 'SHA256:pinned');
    });

    test('is shown as a change, beside the pinned one', () async {
      HostKeyPromptRequest? asked;
      final accepted = await service.verifyHostKey(
        'ssh-ed25519',
        _fingerprint('SHA256:attacker'),
        (request) async {
          asked = request;
          return false;
        },
      );

      expect(accepted, isFalse);
      expect(asked?.verdict, HostKeyVerdict.changed);
      expect(asked?.pinnedFingerprint, 'SHA256:pinned');
      expect(await pinned(), 'SHA256:pinned');
    });
  });

  group('a refused host key is final', () {
    late FakeSshBackend backend;
    late SshSessionManager manager;
    late StreamController<bool> networkChanges;
    late NetworkMonitor network;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      backend = FakeSshBackend();
      manager = SshSessionManager.test(
        remoteAgentService: FakeRemoteAgentService(backend),
        serviceFactory: backend.createService,
      );
      networkChanges = StreamController<bool>.broadcast();
      network = NetworkMonitor(
        changes: networkChanges.stream.map((_) => [ConnectivityResult.wifi]),
        probe: () async => [ConnectivityResult.wifi],
      );
      await network.init();
    });

    tearDown(() async {
      manager.dispose();
      await network.dispose();
      await networkChanges.close();
    });

    for (final reason in [
      SshFailureReason.hostKeyRejected,
      SshFailureReason.hostKeyMismatch,
    ]) {
      test('${reason.name} on a reconnect is not retried', () {
        fakeAsync((async) {
          final container = ProviderContainer.test(
            overrides: [
              sshSessionManagerProvider.overrideWithValue(manager),
              profileStorageProvider.overrideWithValue(
                FakeProfileStorage([profileFixture()]),
              ),
              networkMonitorProvider.overrideWithValue(network),
            ],
          );
          final provider = sshConnectionProvider(('pinned', profileFixture()));
          container.read(provider.notifier).connect();
          async.flushMicrotasks();

          backend.connectError = SshConnectException(reason, 'host key');
          manager.markSessionDropped('pinned');
          async.elapse(const Duration(minutes: 2));

          final state = container.read(provider);
          expect(state.status, ConnectionStatus.error);
          expect(state.failureReason, reason);
          expect(
            backend.calls.where((call) => call.method == 'connect'),
            hasLength(2),
          );
        });
      });
    }
  });
}

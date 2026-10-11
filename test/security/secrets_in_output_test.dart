@Tags(['security'])
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_connection_provider.dart';
import 'package:termphin/providers/ssh_session_manager_provider.dart';
import 'package:termphin/services/analytics/analytics_service.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';

import '../support/fake_master_key_store.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/ssh_fakes.dart';

/// Credentials never show up in anything the app writes out while
/// connecting: the connection log the user can open and share, the error on
/// screen, analytics, or the debug log. Driven through the real [SshService]
/// on a socket that hangs up at once, so the real password callback, key
/// decoding and failure paths run - the fake backend skips all of them.
const _password = 'canary!password';
const _inlineKey = 'canary!inline-private-key';
const _passphrase = 'canary!passphrase';
const _canaries = [_password, _inlineKey, _passphrase];

class _HangUpSocket implements SSHSocket {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const analyticsChannel = MethodChannel('posthog_flutter');
  final written = <String>[];
  late DebugPrintCallback originalDebugPrint;
  late SshSessionManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    written.clear();
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => written.add('debug: $message');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async {
          written.add('analytics: ${call.arguments}');
          return null;
        });
    AnalyticsService.instance.resetForTest();
    await AnalyticsService.instance.setConsent(true);
    final knownHosts = KnownHostsStore(cipher: cipherFixture());
    manager = SshSessionManager.test(
      remoteAgentService: FakeRemoteAgentService(FakeSshBackend()),
      serviceFactory: () => SshService(
        socketConnector: (_, _, {required timeout}) async => _HangUpSocket(),
        knownHosts: knownHosts,
      ),
    );
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    manager.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
  });

  /// Connects [profile] until it fails, and returns everything written.
  Future<String> failToConnect(SshProfile profile) async {
    final container = ProviderContainer.test(
      overrides: [
        sshSessionManagerProvider.overrideWithValue(manager),
        profileStorageProvider.overrideWithValue(FakeProfileStorage([profile])),
      ],
    );
    final provider = sshConnectionProvider(('leak-check', profile));
    await container
        .read(provider.notifier)
        .connect()
        .timeout(const Duration(seconds: 10));
    await pumpEventQueue();
    final state = container.read(provider);
    expect(state.status, isNot(ConnectionStatus.connected));
    return [
      ...written,
      'log: ${state.connectionLog.join('\n')}',
      'error: ${state.errorMessage}',
    ].join('\n');
  }

  void expectNoCanary(String output) {
    for (final canary in _canaries) {
      expect(output, isNot(contains(canary)), reason: '$canary leaked');
    }
  }

  test('a failed password login writes out no password', () async {
    final output = await failToConnect(profileFixture(password: _password));

    expect(output, contains('analytics: '));
    expect(output, contains('error: '));
    expectNoCanary(output);
  });

  test(
    'a key that cannot be read writes out neither key nor passphrase',
    () async {
      final output = await failToConnect(
        profileFixture(
          authMethod: AuthMethod.privateKey,
          password: null,
          privateKey:
              '-----BEGIN OPENSSH PRIVATE KEY-----\n'
              '$_inlineKey\n'
              '-----END OPENSSH PRIVATE KEY-----\n',
          passphrase: _passphrase,
        ),
      );

      expect(output, contains('The key could not be read.'));
      expectNoCanary(output);
    },
  );

  test('a key decode error carries none of the key in its message', () async {
    final error = await resolveIdentities(
      profileFixture(
        authMethod: AuthMethod.privateKey,
        privateKey: 'not a key at all $_inlineKey',
        passphrase: _passphrase,
      ),
    ).then<Object?>((_) => null, onError: (Object error) => error);

    expect(error, isA<SshConnectException>());
    expectNoCanary(error.toString());
  });
}

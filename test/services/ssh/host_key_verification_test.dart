import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/known_host.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

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

/// The bytes dartssh2 hands the callback: UTF-8 `SHA256:<base64>`.
Uint8List fingerprintBytes(String value) =>
    Uint8List.fromList(utf8.encode(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KnownHostsStore knownHosts;
  late SshService service;

  /// Resolves the endpoint the way a real connection does, so the pin is
  /// keyed against the address that was actually reached.
  Future<void> reachHost({List<String> fallbackHosts = const []}) =>
      service.connectSocket(profileFixture(fallbackHosts: fallbackHosts));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    knownHosts = KnownHostsStore(cipher: cipherFixture());
    service = SshService(
      socketConnector: (_, _, {required timeout}) async => _FakeSocket(),
      knownHosts: knownHosts,
    );
  });

  test('an unknown host with no prompt to raise is refused', () async {
    await reachHost();
    expect(
      await service.verifyHostKey(
        'ssh-ed25519',
        fingerprintBytes('SHA256:aaa'),
        null,
      ),
      isFalse,
    );
  });

  test('accepting an unknown host pins it', () async {
    await reachHost();
    final accepted = await service.verifyHostKey(
      'ssh-ed25519',
      fingerprintBytes('SHA256:aaa'),
      (_) async => true,
    );

    expect(accepted, isTrue);
    expect(
      await knownHosts.check(
        'example.com',
        22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:aaa',
      ),
      HostKeyVerdict.trusted,
    );
  });

  test('declining an unknown host pins nothing', () async {
    await reachHost();
    final accepted = await service.verifyHostKey(
      'ssh-ed25519',
      fingerprintBytes('SHA256:aaa'),
      (_) async => false,
    );

    expect(accepted, isFalse);
    expect(await knownHosts.entries(), isEmpty);
  });

  test('a pinned key goes through without asking', () async {
    await knownHosts.trust(
      KnownHost(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:aaa',
        addedAt: DateTime(2026),
      ),
    );
    await reachHost();

    var asked = 0;
    final accepted = await service.verifyHostKey(
      'ssh-ed25519',
      fingerprintBytes('SHA256:aaa'),
      (_) async {
        asked++;
        return true;
      },
    );

    expect(accepted, isTrue);
    expect(asked, 0);
  });

  test('a key that does not match the pin is raised as a change', () async {
    await knownHosts.trust(
      KnownHost(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:old',
        addedAt: DateTime(2026),
      ),
    );
    await reachHost();

    HostKeyPromptRequest? seen;
    await service.verifyHostKey('ssh-ed25519', fingerprintBytes('SHA256:new'), (
      request,
    ) async {
      seen = request;
      return false;
    });

    expect(seen?.verdict, HostKeyVerdict.changed);
    expect(seen?.pinnedFingerprint, 'SHA256:old');
    expect(seen?.fingerprint, 'SHA256:new');
  });

  test('the pin follows the address reached, not the profile host', () async {
    service = SshService(
      socketConnector: (host, _, {required timeout}) async {
        if (host == 'example.com') throw const SocketException('unreachable');
        return _FakeSocket();
      },
      knownHosts: knownHosts,
    );
    await reachHost(fallbackHosts: const ['10.0.0.5:2222']);

    await service.verifyHostKey(
      'ssh-ed25519',
      fingerprintBytes('SHA256:aaa'),
      (_) async => true,
    );

    expect((await knownHosts.entries()).single.host, '10.0.0.5');
    expect((await knownHosts.entries()).single.port, 2222);
  });
}

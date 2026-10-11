@Tags(['security'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';

import '../support/fake_master_key_store.dart';
import '../support/fixtures.dart';

/// Nothing weak is ever offered to a server. An allow-list, not a deny-list:
/// an algorithm a dartssh2 upgrade adds to its defaults fails here until
/// someone has looked at it.
///
/// Out on purpose: SHA-1 anywhere (`ssh-rsa` signatures, `diffie-hellman-*-
/// sha1`, `hmac-sha1`), 1024-bit DH (`group1`), CBC ciphers, `hmac-md5` and the
/// truncated `-96` MACs.
const _allowedKex = {
  'curve25519-sha256',
  'curve25519-sha256@libssh.org',
  'ecdh-sha2-nistp256',
  'ecdh-sha2-nistp384',
  'ecdh-sha2-nistp521',
  'diffie-hellman-group-exchange-sha256',
  'diffie-hellman-group14-sha256',
};
const _allowedHostKeys = {
  'ssh-ed25519',
  'rsa-sha2-512',
  'rsa-sha2-256',
  'ecdsa-sha2-nistp256',
  'ecdsa-sha2-nistp384',
  'ecdsa-sha2-nistp521',
};
const _allowedCiphers = {
  'chacha20-poly1305@openssh.com',
  'aes256-ctr',
  'aes128-ctr',
  'aes256-gcm@openssh.com',
  'aes128-gcm@openssh.com',
};
const _allowedMacs = {
  'hmac-sha2-256-etm@openssh.com',
  'hmac-sha2-512-etm@openssh.com',
  'hmac-sha2-256',
  'hmac-sha2-512',
};

/// A socket that stays open and silent, so the client is built and then
/// waits for a server that never speaks.
class _SilentSocket implements SSHSocket {
  // ignore: close_sinks - left open on purpose; the server never speaks.
  final _incoming = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void destroy() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every algorithm offered is on the allow-list', () {
    expect(
      kSshAlgorithms.kex.map((a) => a.name),
      everyElement(isIn(_allowedKex)),
    );
    expect(
      kSshAlgorithms.hostkey.map((a) => a.name),
      everyElement(isIn(_allowedHostKeys)),
    );
    expect(
      kSshAlgorithms.cipher.map((a) => a.name),
      everyElement(isIn(_allowedCiphers)),
    );
    expect(
      kSshAlgorithms.mac.map((a) => a.name),
      everyElement(isIn(_allowedMacs)),
    );
  });

  test('each list still offers something a modern server accepts', () {
    expect(kSshAlgorithms.kex.first.name, startsWith('curve25519'));
    expect(kSshAlgorithms.hostkey.first.name, 'ssh-ed25519');
    expect(
      kSshAlgorithms.cipher.map((a) => a.name),
      contains('chacha20-poly1305@openssh.com'),
    );
    expect(kSshAlgorithms.mac, isNotEmpty);
  });

  test('the connection is built with exactly that set', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SshService(
      socketConnector: (_, _, {required timeout}) async => _SilentSocket(),
      knownHosts: KnownHostsStore(cipher: cipherFixture()),
    );
    unawaited(service.connect(profileFixture()).catchError((_) {}));
    await pumpEventQueue();

    expect(service.client, isNotNull);
    expect(identical(service.client!.algorithms, kSshAlgorithms), isTrue);

    await service.disconnect();
  });
}

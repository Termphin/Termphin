import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/known_host.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';

import '../../support/fake_master_key_store.dart';

KnownHost hostFixture({
  String host = 'example.com',
  int port = 22,
  String keyType = 'ssh-ed25519',
  String fingerprint = 'SHA256:aaa',
}) => KnownHost(
  host: host,
  port: port,
  keyType: keyType,
  fingerprint: fingerprint,
  addedAt: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KnownHostsStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = KnownHostsStore(cipher: cipherFixture());
  });

  test('a host nobody has pinned is unknown, not trusted', () async {
    expect(
      await store.check(
        'example.com',
        22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:aaa',
      ),
      HostKeyVerdict.unknown,
    );
  });

  test('a pinned fingerprint is trusted on the way back', () async {
    await store.trust(hostFixture());
    expect(
      await store.check(
        'example.com',
        22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:aaa',
      ),
      HostKeyVerdict.trusted,
    );
  });

  test('a different fingerprint for a pinned slot reads as changed', () async {
    await store.trust(hostFixture());
    expect(
      await store.check(
        'example.com',
        22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:bbb',
      ),
      HostKeyVerdict.changed,
    );
  });

  test('a second key type on a pinned host is unknown, not changed', () async {
    await store.trust(hostFixture());
    expect(
      await store.check(
        'example.com',
        22,
        keyType: 'ssh-rsa',
        fingerprint: 'SHA256:ccc',
      ),
      HostKeyVerdict.unknown,
    );
  });

  test('the same address on another port is a separate slot', () async {
    await store.trust(hostFixture());
    expect(
      await store.check(
        'example.com',
        2222,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:aaa',
      ),
      HostKeyVerdict.unknown,
    );
  });

  test(
    'accepting a changed key replaces the pin rather than adding one',
    () async {
      await store.trust(hostFixture());
      await store.trust(hostFixture(fingerprint: 'SHA256:bbb'));
      expect((await store.entries()).length, 1);
      expect(
        await store.check(
          'example.com',
          22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:bbb',
        ),
        HostKeyVerdict.trusted,
      );
    },
  );

  test('forget drops every key type pinned for the address', () async {
    await store.trust(hostFixture());
    await store.trust(hostFixture(keyType: 'ssh-rsa', fingerprint: 'SHA256:c'));
    await store.forget('example.com', 22);
    expect(await store.entries(), isEmpty);
  });

  test('concurrent pins do not overwrite each other', () async {
    await Future.wait([
      store.trust(hostFixture(host: 'a.example')),
      store.trust(hostFixture(host: 'b.example')),
      store.trust(hostFixture(host: 'c.example')),
    ]);
    expect((await store.entries()).map((entry) => entry.host).toSet(), {
      'a.example',
      'b.example',
      'c.example',
    });
  });

  test(
    'a record set that will not open reads as empty, never as trusted',
    () async {
      await store.trust(hostFixture());
      final otherDevice = KnownHostsStore(cipher: cipherFixture(seed: 99));
      expect(
        await otherDevice.check(
          'example.com',
          22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:aaa',
        ),
        HostKeyVerdict.unknown,
      );
    },
  );
}

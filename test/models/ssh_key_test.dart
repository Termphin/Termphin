import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/ssh_key.dart';

import '../support/fixtures.dart';

void main() {
  group('SshKey', () {
    test('round-trips through JSON and encoded storage', () {
      final key = sshKeyFixture(
        keyType: SshKeyType.rsa4096,
        updatedAt: DateTime.utc(2026, 4, 5),
      );

      final decoded = SshKey.decode(key.encode());

      expect(decoded.toJson(), key.toJson());
    });

    test('falls back to ed25519 and createdAt for legacy data', () {
      final json = sshKeyFixture().toJson()
        ..['keyType'] = 'unsupported'
        ..remove('updatedAt');

      final key = SshKey.fromJson(json);

      expect(key.keyType, SshKeyType.ed25519);
      expect(key.updatedAt, key.createdAt);
      expect(key.group, 'General');
      expect(key.toJson().containsKey('tags'), isFalse);
    });

    test(
      'legacy tags read back as first tag as group and toJson never outputs tags',
      () {
        final json = sshKeyFixture().toJson()
          ..remove('group')
          ..['tags'] = ['prod', 'eu'];

        final key = SshKey.fromJson(json);
        expect(key.group, 'prod');
        expect(key.toJson().containsKey('tags'), isFalse);
        expect(key.toJson()['group'], 'prod');
      },
    );

    test('copyWith replaces selected fields', () {
      final original = sshKeyFixture();
      final updated = original.copyWith(
        name: 'Renamed',
        keyType: SshKeyType.rsa2048,
        updatedAt: DateTime.utc(2026, 6, 7),
      );

      expect(updated.name, 'Renamed');
      expect(updated.keyType, SshKeyType.rsa2048);
      expect(updated.privateKeyPem, original.privateKeyPem);
      expect(updated.updatedAt, DateTime.utc(2026, 6, 7));
    });

    test('formats key labels and dates', () {
      expect(SshKeyType.ed25519.label, 'ed25519');
      expect(SshKeyType.rsa2048.label, 'rsa 2048');
      expect(SshKeyType.rsa4096.label, 'rsa 4096');
      expect(
        sshKeyFixture(createdAt: DateTime.utc(2026, 12, 9)).formattedDate,
        'Dec 9, 2026',
      );
    });
  });
}

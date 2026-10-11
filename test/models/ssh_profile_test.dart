import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/ssh_profile.dart';

import '../support/fixtures.dart';

void main() {
  group('SshProfile', () {
    test('round-trips all fields through JSON', () {
      final rule = forwardingRuleFixture();
      final profile = profileFixture(
        authMethod: AuthMethod.privateKey,
        password: null,
        privateKey: 'pem',
        passphrase: 'phrase',
        sshKeyId: 'key-1',
        lastConnectedAt: DateTime.utc(2026, 4, 5),
        portForwardings: [rule],
      );

      final decoded = SshProfile.fromJson(profile.toJson());

      expect(decoded.toJson(), profile.toJson());
    });

    test('round-trips encoded profile lists in order', () {
      final profiles = [
        profileFixture(id: 'first'),
        profileFixture(id: 'second'),
      ];

      final decoded = SshProfile.decodeList(SshProfile.encodeList(profiles));

      expect(decoded.map((profile) => profile.id), ['first', 'second']);
    });

    test('uses safe defaults for optional and unknown values', () {
      final json = profileFixture().toJson()
        ..remove('updatedAt')
        ..remove('lastConnectedAt')
        ..remove('portForwardings')
        ..remove('group')
        ..remove('iconName')
        ..remove('colorHex')
        ..['authMethod'] = 'unsupported';

      final profile = SshProfile.fromJson(json);

      expect(profile.authMethod, AuthMethod.password);
      expect(profile.updatedAt, profile.createdAt);
      expect(profile.lastConnectedAt, isNull);
      expect(profile.portForwardings, isEmpty);
      expect(profile.group, 'General');
      expect(profile.iconName, isNull);
      expect(profile.colorHex, isNull);
      expect(profile.toJson().containsKey('tags'), isFalse);
    });

    test(
      'legacy tags read back as first tag as group and toJson never outputs tags',
      () {
        final json = profileFixture().toJson()
          ..remove('group')
          ..['tags'] = ['prod', 'eu'];
        final decoded = SshProfile.fromJson(json);
        expect(decoded.group, 'prod');
        expect(decoded.toJson().containsKey('tags'), isFalse);
        expect(decoded.toJson()['group'], 'prod');
      },
    );

    test('copyWith can explicitly clear all nullable secrets and metadata', () {
      final original = profileFixture(
        authMethod: AuthMethod.privateKey,
        password: 'old-password',
        privateKey: 'old-key',
        passphrase: 'old-passphrase',
        sshKeyId: 'old-key-id',
        lastConnectedAt: DateTime.utc(2026, 5, 6),
      );

      final updated = original.copyWith(
        clearPassword: true,
        clearPrivateKey: true,
        clearPassphrase: true,
        clearSshKeyId: true,
        clearLastConnectedAt: true,
        clearIconName: true,
        clearColorHex: true,
      );

      expect(updated.password, isNull);
      expect(updated.privateKey, isNull);
      expect(updated.passphrase, isNull);
      expect(updated.sshKeyId, isNull);
      expect(updated.lastConnectedAt, isNull);
      expect(updated.iconName, isNull);
      expect(updated.colorHex, isNull);
      expect(updated.id, original.id);
    });

    test('encode and decode preserve the profile', () {
      final profile = profileFixture();

      expect(SshProfile.decode(profile.encode()).toJson(), profile.toJson());
    });
  });

  group('connectionCandidates', () {
    test(
      'is host followed by fallbackHosts when nothing has succeeded yet',
      () {
        final profile = profileFixture(
          host: 'primary.example.com',
          fallbackHosts: ['10.0.0.1', 'fallback.example.com'],
        );

        expect(profile.connectionCandidates, [
          'primary.example.com',
          '10.0.0.1',
          'fallback.example.com',
        ]);
      },
    );

    test('keeps host first and moves lastGoodHost ahead of the fallbacks', () {
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['10.0.0.1', 'fallback.example.com'],
        lastGoodHost: 'fallback.example.com',
      );

      expect(profile.connectionCandidates, [
        'primary.example.com',
        'fallback.example.com',
        '10.0.0.1',
      ]);
    });

    test('leads with lastGoodHost when mainHostFirst is off', () {
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['10.0.0.1', 'fallback.example.com'],
        lastGoodHost: 'fallback.example.com',
        mainHostFirst: false,
      );

      expect(profile.connectionCandidates, [
        'fallback.example.com',
        'primary.example.com',
        '10.0.0.1',
      ]);
    });

    test('keeps host first with mainHostFirst off until a fallback works', () {
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['10.0.0.1'],
        mainHostFirst: false,
      );

      expect(profile.connectionCandidates, ['primary.example.com', '10.0.0.1']);
    });

    test('ignores a lastGoodHost that is no longer in the queue', () {
      final profile = profileFixture(
        host: 'primary.example.com',
        fallbackHosts: ['10.0.0.1'],
        lastGoodHost: 'old.example.com',
      );

      expect(profile.connectionCandidates, ['primary.example.com', '10.0.0.1']);
    });

    test('round-trips fallbackHosts and lastGoodHost through JSON', () {
      final profile = profileFixture(
        fallbackHosts: ['10.0.0.1', 'fallback.example.com'],
        lastGoodHost: '10.0.0.1',
      );

      final decoded = SshProfile.fromJson(profile.toJson());

      expect(decoded.fallbackHosts, profile.fallbackHosts);
      expect(decoded.lastGoodHost, profile.lastGoodHost);
    });

    test('round-trips mainHostFirst through JSON', () {
      final profile = profileFixture(mainHostFirst: false);

      expect(SshProfile.fromJson(profile.toJson()).mainHostFirst, isFalse);
    });

    test('a profile saved before mainHostFirst existed keeps host first', () {
      final json = profileFixture().toJson()..remove('mainHostFirst');

      expect(SshProfile.fromJson(json).mainHostFirst, isTrue);
    });
  });

  group('SshEndpoint.parse', () {
    test('a bare host uses the default port', () {
      final endpoint = SshEndpoint.parse('10.0.0.1', defaultPort: 22);
      expect(endpoint.host, '10.0.0.1');
      expect(endpoint.port, 22);
    });

    test('host:port overrides the default port', () {
      final endpoint = SshEndpoint.parse('10.0.0.1:2222', defaultPort: 22);
      expect(endpoint.host, '10.0.0.1');
      expect(endpoint.port, 2222);
    });

    test(
      'an unparseable port falls back to the default rather than crashing',
      () {
        final endpoint = SshEndpoint.parse('10.0.0.1:abc', defaultPort: 22);
        expect(endpoint.host, '10.0.0.1:abc');
        expect(endpoint.port, 22);
      },
    );

    test('a bare IPv6 literal is not mistaken for host:port', () {
      final endpoint = SshEndpoint.parse('::1', defaultPort: 22);
      expect(endpoint.host, '::1');
      expect(endpoint.port, 22);
    });

    test('a bracketed IPv6 literal can still carry a port override', () {
      final endpoint = SshEndpoint.parse('[::1]:2222', defaultPort: 22);
      expect(endpoint.host, '::1');
      expect(endpoint.port, 2222);
    });
  });
}

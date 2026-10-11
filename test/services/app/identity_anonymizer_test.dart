import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/app/legal_urls.dart';

void main() {
  group('IdentityAnonymizer', () {
    test('the same seed always produces the same fake identity', () {
      final name = IdentityAnonymizer.name('seed-1');
      final user = IdentityAnonymizer.username('seed-1');
      final host = IdentityAnonymizer.host('seed-1');
      for (var i = 0; i < 3; i++) {
        expect(IdentityAnonymizer.name('seed-1'), name);
        expect(IdentityAnonymizer.username('seed-1'), user);
        expect(IdentityAnonymizer.host('seed-1'), host);
      }
    });

    test('different seeds usually produce different identities', () {
      final names = {
        for (var i = 0; i < 50; i++) IdentityAnonymizer.name('profile-$i'),
      };
      expect(names.length, greaterThan(1));
    });

    test('names come from the fixed word list', () {
      const allowed = {
        'atlas',
        'nimbus',
        'harbor',
        'quartz',
        'ember',
        'cobalt',
        'meadow',
        'falcon',
        'lagoon',
        'summit',
        'cinder',
        'ridge',
      };
      for (var i = 0; i < 100; i++) {
        expect(allowed, contains(IdentityAnonymizer.name('s$i')));
      }
    });

    test('usernames come from the fixed user list', () {
      const allowed = {'deploy', 'admin', 'ops', 'svc', 'runner'};
      for (var i = 0; i < 100; i++) {
        expect(allowed, contains(IdentityAnonymizer.username('s$i')));
      }
    });

    test('hosts are private-range IPv4 addresses', () {
      final regexp = RegExp(r'^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
      for (var i = 0; i < 100; i++) {
        final host = IdentityAnonymizer.host('s$i');
        expect(host, matches(regexp));
        for (final octet in host.split('.').skip(1).map(int.parse)) {
          expect(octet, lessThan(256));
        }
      }
    });
  });

  group('LegalUrls', () {
    test('point at the published legal pages', () {
      expect(LegalUrls.privacyPolicy, 'https://termphin.dev/privacy');
      expect(LegalUrls.termsOfService, 'https://termphin.dev/terms');
    });
  });
}

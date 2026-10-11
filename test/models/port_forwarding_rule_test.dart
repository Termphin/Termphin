import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/models/port_forwarding_rule.dart';

import '../support/fixtures.dart';

void main() {
  group('PortForwardingRule', () {
    test('uses explicit name or a directional default label', () {
      expect(forwardingRuleFixture(name: 'Database').displayName, 'Database');
      expect(
        forwardingRuleFixture(name: null).displayName,
        'L:5432→db.internal:5432',
      );
      expect(
        forwardingRuleFixture(
          name: null,
          type: ForwardType.remote,
          localPort: 8080,
          remotePort: 80,
        ).displayName,
        'R:8080→db.internal:80',
      );
    });

    test('round-trips through JSON', () {
      final rule = forwardingRuleFixture(type: ForwardType.remote);

      expect(
        PortForwardingRule.fromJson(rule.toJson()).toJson(),
        rule.toJson(),
      );
    });

    test('uses safe defaults for legacy and unknown fields', () {
      final json = forwardingRuleFixture().toJson()
        ..['type'] = 'unsupported'
        ..remove('localHost');

      final rule = PortForwardingRule.fromJson(json);

      expect(rule.type, ForwardType.local);
      expect(rule.localHost, 'localhost');
    });

    test('copyWith can clear the optional name', () {
      final original = forwardingRuleFixture(name: 'Database');

      final updated = original.copyWith(clearName: true, localPort: 15432);

      expect(updated.name, isNull);
      expect(updated.localPort, 15432);
      expect(updated.remoteHost, original.remoteHost);
    });
  });
}

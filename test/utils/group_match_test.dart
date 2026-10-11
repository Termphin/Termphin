import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/utils/group_match.dart';

void main() {
  group('isSameGroup', () {
    test('equal names match', () {
      expect(isSameGroup('Servers', 'Servers'), isTrue);
      expect(isSameGroup('dev', 'dev'), isTrue);
    });

    test('differing case matches', () {
      expect(isSameGroup('Servers', 'servers'), isTrue);
      expect(isSameGroup('DevOps', 'DEVOPS'), isTrue);
      expect(isSameGroup('pRoD', 'Prod'), isTrue);
    });

    test('surrounding whitespace is ignored', () {
      expect(isSameGroup('  Servers  ', 'Servers'), isTrue);
      expect(isSameGroup('\tServers\n', 'servers'), isTrue);
      expect(isSameGroup('  DevOps', 'devops  '), isTrue);
    });

    test('genuinely different names do not match', () {
      expect(isSameGroup('Servers', 'Clients'), isFalse);
      expect(isSameGroup('Prod', 'Production'), isFalse);
      expect(isSameGroup('Dev', 'Staging'), isFalse);
    });
  });

  group('resolveGroupName', () {
    test("returns the list's spelling", () {
      final known = ['Production', 'Staging', 'General'];
      expect(resolveGroupName('production', known), 'Production');
      expect(resolveGroupName('  PRODUCTION  ', known), 'Production');
      expect(resolveGroupName('STAGING', known), 'Staging');
      expect(resolveGroupName('general', known), 'General');
    });

    test('returns null when absent', () {
      final known = ['Production', 'Staging', 'General'];
      expect(resolveGroupName('DevOps', known), isNull);
      expect(resolveGroupName('Prod', known), isNull);
      expect(resolveGroupName('', known), isNull);
      expect(resolveGroupName('unknown', <String>[]), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/app/version_compare.dart';

void main() {
  group('compareVersions', () {
    test('orders by each component, most significant first', () {
      expect(compareVersions('1.2.3', '1.2.4'), isNegative);
      expect(compareVersions('1.3.0', '1.2.9'), isPositive);
      expect(compareVersions('2.0.0', '1.9.9'), isPositive);
    });

    test('compares numerically, not as text', () {
      expect(compareVersions('0.10.0', '0.9.0'), isPositive);
      expect(compareVersions('1.0.11', '1.0.2'), isPositive);
    });

    test('pads a shorter version with zeroes', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.2', '1.2.1'), isNegative);
      expect(compareVersions('1.2.1', '1.2'), isPositive);
    });

    test('is its own inverse', () {
      expect(compareVersions('1.4.0', '1.4.0'), 0);
      expect(
        compareVersions('3.1.0', '2.9.9').sign,
        -compareVersions('2.9.9', '3.1.0').sign,
      );
    });

    test('sorts a release list oldest first', () {
      final versions = ['1.10.0', '1.2.0', '0.9.5', '1.2.10', '1.2.2'];
      versions.sort(compareVersions);
      expect(versions, ['0.9.5', '1.2.0', '1.2.2', '1.2.10', '1.10.0']);
    });

    test('throws on a version that is not dotted numbers', () {
      expect(
        () => compareVersions('1.2.0-beta', '1.2.0'),
        throwsFormatException,
      );
      expect(() => compareVersions('v1.2.0', '1.2.0'), throwsFormatException);
      expect(() => compareVersions('', '1.0.0'), throwsFormatException);
    });
  });

  group('isReleasedVersion', () {
    test('accepts the dotted numbers compareVersions can order', () {
      expect(isReleasedVersion('1.2.0'), isTrue);
      expect(isReleasedVersion('1.2'), isTrue);
      expect(isReleasedVersion('0'), isTrue);
    });

    test('rejects anything that would throw on the way to a comparison', () {
      expect(isReleasedVersion('Unreleased'), isFalse);
      expect(isReleasedVersion('1.2.0-beta'), isFalse);
      expect(isReleasedVersion('v1.2.0'), isFalse);
      expect(isReleasedVersion(''), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/pro/pro_service.dart';

void main() {
  group('serverAfterCheck', () {
    test('the check answer replaces the claim the token carried', () {
      expect(serverAfterCheck(true, false), isFalse);
      expect(serverAfterCheck(false, true), isTrue);
    });

    test('a check that gave no answer keeps the claim the token carried', () {
      expect(serverAfterCheck(true, null), isTrue);
      expect(serverAfterCheck(false, null), isFalse);
    });
  });
}

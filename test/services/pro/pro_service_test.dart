import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
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

  test(
    'a store subscription keeps billing after the account is deleted, a web one does not',
    () {
      expect(storeKeepsBilling(Store.appStore), isTrue);
      expect(storeKeepsBilling(Store.macAppStore), isTrue);
      expect(storeKeepsBilling(Store.playStore), isTrue);
      expect(storeKeepsBilling(Store.stripe), isFalse);
      expect(storeKeepsBilling(Store.rcBilling), isFalse);
      expect(storeKeepsBilling(Store.paddle), isFalse);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:termphin/screens/pro/pro_paywall_screen.dart';
import 'package:termphin/services/pro/pro_service.dart';

class _FakePackage extends Fake implements Package {}

ProOffer _offer(String period, {double? amount}) => ProOffer(
  package: _FakePackage(),
  price: '',
  period: period,
  amount: amount,
);

void main() {
  group('sortedOffers', () {
    test('yearly first, then monthly, then anything else', () {
      final sorted = sortedOffers([
        _offer('lifetime'),
        _offer('monthly'),
        _offer('annual'),
      ]);

      expect(sorted.map((offer) => offer.period), [
        'annual',
        'monthly',
        'lifetime',
      ]);
    });

    test('an empty list stays empty', () {
      expect(sortedOffers(const []), isEmpty);
    });
  });

  group('savingPercent', () {
    test('what a year saves against twelve months, in whole percent', () {
      expect(
        savingPercent(
          _offer('annual', amount: 90),
          _offer('monthly', amount: 10),
        ),
        25,
      );
    });

    test('a saving under five percent is not worth saying', () {
      expect(
        savingPercent(
          _offer('annual', amount: 117),
          _offer('monthly', amount: 10),
        ),
        isNull,
      );
    });

    test('nothing is said without a monthly plan or usable prices', () {
      expect(savingPercent(_offer('annual', amount: 90), null), isNull);
      expect(
        savingPercent(_offer('annual'), _offer('monthly', amount: 10)),
        isNull,
      );
      expect(
        savingPercent(
          _offer('annual', amount: 90),
          _offer('monthly', amount: 0),
        ),
        isNull,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:termphin/services/pro/pro_service.dart';

void main() {
  test('a trial in days or weeks is counted in days', () {
    expect(trialDaysOf(1, PeriodUnit.week), 7);
    expect(trialDaysOf(2, PeriodUnit.week), 14);
    expect(trialDaysOf(3, PeriodUnit.day), 3);
  });

  group('claimSaysPro', () {
    final now = DateTime.utc(2026, 11, 14, 14);
    final ms = now.millisecondsSinceEpoch;

    test('counts Pro until the expiry the token carries', () {
      expect(claimSaysPro({'pro': true, 'proUntil': ms + 1}, now), isTrue);
      expect(claimSaysPro({'pro': true, 'proUntil': ms}, now), isFalse);
    });

    test('counts a lifetime purchase, which has no expiry', () {
      expect(claimSaysPro({'pro': true}, now), isTrue);
    });

    test('counts nothing without the claim', () {
      expect(claimSaysPro({'pro': false}, now), isFalse);
      expect(claimSaysPro(null, now), isFalse);
    });
  });

  test('a month is no fixed number of days to promise', () {
    expect(trialDaysOf(1, PeriodUnit.month), isNull);
    expect(trialDaysOf(1, PeriodUnit.year), isNull);
  });
}

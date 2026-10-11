import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/ui/new_badge.dart';

void main() {
  test('a row is new until the app reaches the version it names', () {
    expect(isStillNew('1.9.0', '1.11.0'), isTrue);
    expect(isStillNew('1.10.3', '1.11.0'), isTrue);
    expect(isStillNew('1.11.0', '1.11.0'), isFalse);
    expect(isStillNew('2.0.0', '1.11.0'), isFalse);
  });

  test('an unknown version shows no badge', () {
    expect(isStillNew(null, '1.11.0'), isFalse);
    expect(isStillNew('1.10.0-beta', '1.11.0'), isFalse);
  });
}

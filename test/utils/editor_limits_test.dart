import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/utils/editor_limits.dart';

void main() {
  test('a file the phone can hold opens', () {
    expect(isTooLargeToEdit(0), isFalse);
    expect(isTooLargeToEdit(1024), isFalse);
    expect(isTooLargeToEdit(kMaxEditableBytes), isFalse);
  });

  test('a log too big for the heap is refused', () {
    expect(isTooLargeToEdit(kMaxEditableBytes + 1), isTrue);
    expect(isTooLargeToEdit(192 * 1024 * 1024), isTrue);
  });

  test('a server that reports no size is not refused on that alone', () {
    expect(isTooLargeToEdit(null), isFalse);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/reconnect_input_buffer.dart';

void main() {
  late ReconnectInputBuffer buffer;

  setUp(() => buffer = ReconnectInputBuffer());

  String taken() => utf8.decode(buffer.take());

  test('keeps printable text in order', () {
    buffer.add(utf8.encode('ls '));
    buffer.add(utf8.encode('-la'));

    expect(taken(), 'ls -la');
    expect(buffer.isEmpty, isTrue);
  });

  test('keeps text outside ASCII whole', () {
    buffer.add(utf8.encode('zażółć'));

    expect(taken(), 'zażółć');
  });

  test('never keeps Enter - a command run blind is the danger', () {
    expect(buffer.add([0x0d]), isFalse);
    expect(buffer.add([0x0a]), isFalse);

    expect(buffer.isEmpty, isTrue);
  });

  test('drops a chunk carrying any control byte as a whole', () {
    expect(buffer.add(utf8.encode('rm -rf build\nmake')), isFalse);
    expect(buffer.add([0x1b, 0x5b, 0x41]), isFalse, reason: 'arrow up');
    expect(buffer.add([0x03]), isFalse, reason: 'Ctrl-C');

    expect(buffer.isEmpty, isTrue);
  });

  test('backspace takes back the last character typed', () {
    buffer.add(utf8.encode('gti'));
    buffer.add([0x7f]);
    buffer.add([0x7f]);
    buffer.add(utf8.encode('it'));

    expect(taken(), 'git');
  });

  test('backspace removes a whole multi-byte character', () {
    buffer.add(utf8.encode('aż'));
    buffer.add([0x08]);

    expect(taken(), 'a');
  });

  test('backspace on nothing is not queued for the server', () {
    expect(buffer.add([0x7f]), isFalse);

    expect(buffer.isEmpty, isTrue);
  });

  test('stops taking text past its limit', () {
    buffer.add(List.filled(ReconnectInputBuffer.maxBytes, 0x61));

    expect(buffer.add([0x62]), isFalse);
    expect(buffer.length, ReconnectInputBuffer.maxBytes);
  });

  test('counts characters, not bytes', () {
    buffer.add(utf8.encode('żż'));

    expect(buffer.characters, 2);
  });

  test('clear forgets everything', () {
    buffer.add(utf8.encode('secret'));
    buffer.clear();

    expect(buffer.isEmpty, isTrue);
    expect(buffer.take(), isEmpty);
  });
}

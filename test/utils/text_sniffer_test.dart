import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/utils/text_sniffer.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

Uint8List _text(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  test('plain text and empty files are editable', () {
    expect(probeTextContent(_text('')).isText, isTrue);
    expect(probeTextContent(_text('#!/bin/sh\necho hi\n')).isText, isTrue);
    expect(probeTextContent(_text('zażółć gęślą jaźń')).isText, isTrue);
    expect(
      probeTextContent(_bytes([0xef, 0xbb, 0xbf, ...utf8.encode('ok')])).isText,
      isTrue,
    );
  });

  test('a NUL byte marks the file binary', () {
    final probe = probeTextContent(_bytes([0x68, 0x69, 0x00, 0x68]));

    expect(probe.isText, isFalse);
    expect(probe.reason, BinaryReason.nulByte);
  });

  test('invalid UTF-8 marks the file binary', () {
    final probe = probeTextContent(_bytes([0x68, 0xc3, 0x28, 0x69]));

    expect(probe.isText, isFalse);
    expect(probe.reason, BinaryReason.invalidUtf8);
  });

  test('a character cut off by the read is not held against the file', () {
    final head = _bytes([...utf8.encode('aaa'), 0xc4]);

    expect(probeTextContent(head, truncated: true).isText, isTrue);
    expect(probeTextContent(head).isText, isFalse);
  });

  test('UTF-16 is rejected because saving would rewrite it as UTF-8', () {
    final probe = probeTextContent(_bytes([0xff, 0xfe, 0x68, 0x00]));

    expect(probe.isText, isFalse);
    expect(probe.reason, BinaryReason.wideEncoding);
  });

  test('mostly control bytes counts as binary', () {
    final probe = probeTextContent(
      _bytes([for (var i = 0; i < 40; i++) i.isEven ? 0x41 : 0x01]),
    );

    expect(probe.isText, isFalse);
    expect(probe.reason, BinaryReason.controlBytes);
  });

  test('tabs, newlines and ANSI escapes stay text', () {
    final log = _bytes([
      ...utf8.encode('line\tone\r\n'),
      0x1b,
      0x5b,
      0x33,
      0x31,
      0x6d,
      ...utf8.encode('red\n'),
    ]);

    expect(probeTextContent(log).isText, isTrue);
  });
}

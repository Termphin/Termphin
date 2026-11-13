import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/terminal_notification.dart';

void main() {
  TerminalNotification? parse(String sequence) {
    final fields = sequence.split(';');
    return TerminalNotification.fromOsc(fields.first, fields.sublist(1));
  }

  test('iTerm2: OSC 9 is the message, as Claude Code sends it', () {
    expect(
      parse('9;Claude is waiting for your input'),
      const TerminalNotification(title: 'Claude is waiting for your input'),
    );
  });

  test('iTerm2: a semicolon in the message stays in it', () {
    expect(parse('9;done; 3 warnings')?.title, 'done; 3 warnings');
  });

  test('ConEmu reuses OSC 9 for numbered commands, which are not messages', () {
    expect(parse('9;4;1;50'), isNull);
    expect(parse('9;9;/home/me'), isNull);
  });

  test('rxvt: OSC 777 notify has a title and a body', () {
    expect(
      parse('777;notify;Build;finished in 42s'),
      const TerminalNotification(title: 'Build', body: 'finished in 42s'),
    );
    expect(parse('777;preexec'), isNull);
  });

  test('kitty: OSC 99 is a title unless it says otherwise', () {
    expect(
      parse('99;;Tests passed'),
      const TerminalNotification(title: 'Tests passed'),
    );
    expect(
      parse('99;i=1:p=body;all green'),
      const TerminalNotification(title: '', body: 'all green'),
    );
    final encoded = base64.encode(utf8.encode('zażółć'));
    expect(parse('99;e=1;$encoded')?.title, 'zażółć');
    expect(parse('99;p=icon;x'), isNull);
  });

  test('other OSCs are not notifications', () {
    expect(parse('0;window title'), isNull);
    expect(parse('52;c;aGVsbG8='), isNull);
    expect(parse('5380;termphin-replay-end'), isNull);
  });

  test('an empty one is nothing to announce', () {
    expect(parse('9; '), isNull);
    expect(parse('777;notify;;'), isNull);
  });

  test('what reaches a banner is one line of text, not escapes', () {
    final notification = parse(
      '777;notify;a\x1b[31mred\x07;line one\nline two',
    );

    expect(notification?.title, 'a [31mred');
    expect(notification?.body, 'line one line two');
  });

  test('a novel is cut short', () {
    final title = parse('9;${'x' * 1000}')!.title;

    expect(title.length, TerminalNotification.maxLength);
    expect(title, endsWith('…'));
  });
}

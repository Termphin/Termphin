import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/services/completion/command_line_reader.dart';

void main() {
  late Terminal terminal;
  late CommandLineReader reader;

  setUp(() {
    terminal = Terminal()..resize(20, 5);
    reader = CommandLineReader(terminal);
  });

  /// Types [text] and has the shell echo it.
  void type(String text) {
    reader.userInput(text);
    terminal.write(text);
  }

  test('reads what follows the prompt the first key was typed after', () {
    terminal.write('host:~% ');
    type('git st');

    expect(reader.read(), 'git st');
  });

  test('keeps a trailing space, which starts a new word', () {
    terminal.write('> ');
    type('ls ');

    expect(reader.read(), 'ls ');
  });

  test('reads a command wrapped over several rows', () {
    terminal.write('host:~% ');
    type('echo abcdefghijklmnopqrstuvwxyz');

    expect(reader.read(), 'echo abcdefghijklmnopqrstuvwxyz');
  });

  test('the prompt is not part of the line even when nothing is typed', () {
    terminal.write('host:~% ');
    reader.userInput('\x1b[A');
    terminal.write('make');

    expect(reader.read(), 'make');
  });

  test('a key sent before the prompt was drawn falls back on its shape', () {
    terminal.write('output\r\n');
    reader.userInput('l');
    terminal.write('user@box:~\$ l');

    expect(reader.read(), 'l');
  });

  test('a prompt-shaped piece of the command is not taken for the prompt', () {
    terminal.write('\$ ');
    type('echo a > b');

    expect(reader.read(), 'echo a > b');
  });

  test('Enter reports the submitted line and starts the next one', () {
    final submitted = <String>[];
    reader.onSubmit = submitted.add;
    terminal.write('> ');
    type('uptime');
    reader.userInput('\r');
    terminal.write('\r\n 12:00 up\r\n> ');
    type('w');

    expect(submitted, ['uptime']);
    expect(reader.read(), 'w');
  });

  test('a password typed blind is never reported', () {
    final submitted = <String>[];
    reader.onSubmit = submitted.add;
    terminal.write('[sudo] password: ');
    reader.userInput('hunter2\r');

    expect(submitted, isEmpty);
  });

  test('nothing is read from a full-screen program', () {
    terminal.write('> ');
    type('vim');
    terminal.write('\x1b[?1049h');

    expect(reader.read(), isNull);
  });

  test('no prompt in sight reads as nothing', () {
    terminal.write('plain output');

    expect(reader.read(), isNull);
  });

  test('output before anything is typed is not read as a command', () {
    terminal.write('> ');
    type('cat log');
    reader.userInput('\r');
    terminal.write('\r\nuser@box:~\$ was here');

    expect(reader.read(), isNull);
  });

  test('text after the cursor is noticed, a right-hand prompt is not', () {
    terminal.write('> git');
    expect(reader.textFollowsCursor(), isFalse);

    terminal.write(' status\x1b[7D');
    expect(reader.textFollowsCursor(), isTrue);

    terminal.write('\x1b[2K\r> ls      12:00\x1b[11D');
    expect(reader.textFollowsCursor(), isFalse);
  });
}

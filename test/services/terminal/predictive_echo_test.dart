import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/services/terminal/predictive_echo.dart';

void main() {
  late Terminal terminal;
  late PredictiveEcho echo;
  var now = 0;

  setUp(() {
    now = 0;
    terminal = Terminal()..resize(20, 5);
    echo = PredictiveEcho(terminal)
      ..clock = (() => now)
      ..attach()
      ..enabled = true;
  });

  tearDown(() => echo.dispose());

  /// Predicted cells as `row:column:char`, a blank as a space.
  List<String> shown() => [
    for (final c in echo.cells)
      '${c.row}:${c.column}:${_char(c.cell.content & CellContent.codepointMask)}',
  ];

  /// Types a key and has the server echo it [latency] ms later.
  void typeAndEcho(String key, {int latency = 100, String? reply}) {
    echo.userInput(key);
    now += latency;
    terminal.write(reply ?? key);
  }

  test('the first key of a line is not shown before its echo', () {
    echo.userInput('a');

    expect(shown(), isEmpty);
    expect(echo.cursor, isNull);
  });

  test('once an echo confirmed the line, later keys show at once', () {
    typeAndEcho('a');

    now += 10;
    echo.userInput('b');

    expect(shown(), ['0:1:b']);
    expect(echo.cursor, const CellOffset(2, 0));
  });

  test('the echo replaces the prediction', () {
    typeAndEcho('a');
    typeAndEcho('b');

    expect(shown(), isEmpty);
    expect(echo.cursor, const CellOffset(2, 0));
    expect(terminal.buffer.lines[0].getText().trim(), 'ab');
  });

  test('keys typed after Enter stay hidden while nothing echoes them', () {
    typeAndEcho('a');

    echo.userInput('\r');
    echo.userInput('s');
    echo.userInput('e');

    expect(shown(), isEmpty);
    expect(echo.cursor, isNull);
  });

  test('a server that draws something else wipes the predictions', () {
    typeAndEcho('a');
    echo.userInput('b');
    expect(shown(), ['0:1:b']);

    now += 5;
    terminal.write('Z');

    expect(shown(), isEmpty);
  });

  test('a prediction nobody answers is given up on', () {
    typeAndEcho('a');
    echo.userInput('b');

    now += 5000;
    echo.tick();

    expect(shown(), isEmpty);
    expect(echo.cursor, isNull);
  });

  test('nothing is shown on a fast link', () {
    typeAndEcho('a', latency: 10);

    echo.userInput('b');

    expect(shown(), isEmpty);
  });

  test('a moderately slow link shows predictions plainly', () {
    typeAndEcho('a', latency: 90);

    echo.userInput('b');

    expect(shown(), ['0:1:b']);
    expect(echo.dimmed, isFalse);
  });

  test('a very slow link dims them', () {
    typeAndEcho('a', latency: 300);

    echo.userInput('b');

    expect(shown(), ['0:1:b']);
    expect(echo.dimmed, isTrue);
  });

  test('typing along an autosuggestion takes it over in place', () {
    typeAndEcho('g', reply: 'git status\x1b[1;2H');

    echo.userInput('i');

    expect(shown(), ['0:1:i']);
    expect(echo.cursor, const CellOffset(2, 0));
  });

  test('a key that breaks the suggestion waits for its echo', () {
    typeAndEcho('g', reply: 'git status\x1b[1;2H');

    echo.userInput('o');

    expect(shown(), isEmpty);
    expect(echo.cursor, isNull);
  });

  test('once that echo lands, typing at the end is predicted again', () {
    typeAndEcho('g', reply: 'git status\x1b[1;2H');
    typeAndEcho('o', reply: 'o\x1b[K');

    echo.userInput('x');

    expect(shown(), ['0:2:x']);
  });

  test('an insert in the middle of a line waits for its echo', () {
    terminal.write('ad\x1b[1;2H');
    typeAndEcho('x', reply: 'xd\x1b[1;3H');

    echo.userInput('y');

    expect(shown(), isEmpty);
  });

  test('a backspace in the middle of a line waits for its echo', () {
    terminal.write('abcd\x1b[1;3H');
    typeAndEcho('x', reply: 'xcd\x1b[1;4H');

    echo.userInput('\x7f');

    expect(shown(), isEmpty);
  });

  test('a late echo is waited for while other output arrives', () {
    typeAndEcho('a');
    echo.userInput('b');

    now += 350;
    terminal.write('\x1b7\x1b[4;1Hclock\x1b8');

    expect(shown(), ['0:1:b']);
  });

  test('a right-hand prompt past a gap is left where it is', () {
    terminal.write('ab        RP\x1b[1;3H');
    typeAndEcho('c');

    echo.userInput('d');

    expect(shown(), ['0:3:d']);
  });

  test('backspace moves the cursor back and leaves the text to the echo', () {
    typeAndEcho('a');
    typeAndEcho('b');

    echo.userInput('\x7f');

    expect(shown(), isEmpty);
    expect(echo.cursor, const CellOffset(1, 0));
  });

  test('backspace never goes into the prompt', () {
    terminal.write(r'$ ');
    typeAndEcho('a');

    echo.userInput('\x7f');
    expect(echo.cursor, const CellOffset(2, 0));

    echo.userInput('\x7f');
    expect(echo.cursor, isNull);
    expect(shown(), isEmpty);
  });

  test('arrow keys move the predicted cursor', () {
    typeAndEcho('a');
    typeAndEcho('b');

    echo.userInput('\x1b[D');

    expect(echo.cursor, const CellOffset(1, 0));
  });

  test('after Enter, prediction resumes once the server has caught up', () {
    typeAndEcho('a');
    typeAndEcho('\r', reply: '\r\n');
    now += 1000;
    typeAndEcho('l');

    echo.userInput('s');

    expect(shown(), ['1:1:s']);
  });

  test('a newline on the bottom row follows the scroll', () {
    terminal.write('\x1b[5;1H');
    typeAndEcho('a');
    typeAndEcho('\r', reply: '\r\n');
    now += 1000;
    typeAndEcho('l');

    echo.userInput('s');

    expect(shown(), ['4:1:s']);
  });

  test(
    'with receipts, prediction resumes as soon as the server has it all',
    () {
      typeAndEcho('a');
      echo.userInput('\r', 10);
      now += 100;
      echo.acknowledge(10);
      terminal.write('\r\n');
      now += 150;
      echo.tick();

      typeAndEcho('l');
      echo.userInput('s');

      expect(shown(), ['1:1:s']);
    },
  );

  test('without them, a key after Enter is not predicted straight away', () {
    typeAndEcho('a');
    typeAndEcho('\r', reply: '\r\n');
    typeAndEcho('l');

    echo.userInput('s');

    expect(shown(), isEmpty);
  });

  test('full-screen programs get no predictions', () {
    typeAndEcho('a');
    terminal.write('\x1b[?1049h');

    echo.userInput('j');

    expect(shown(), isEmpty);
    expect(echo.cursor, isNull);
  });

  test('stays quiet inside a full-screen program', () {
    typeAndEcho('a');
    echo.userInput('\r');
    terminal.write('\x1b[?1049h');
    var repaints = 0;
    terminal.addListener(() => repaints++);

    for (var i = 0; i < 20; i++) {
      now += 250;
      echo.tick();
    }

    expect(repaints, 0);
  });

  test('never repaints a frame the program is holding back', () {
    typeAndEcho('a');
    terminal.write('\x1b[?2026h');
    var repaints = 0;
    terminal.addListener(() => repaints++);

    echo.userInput('b');
    now += 250;
    echo.tick();

    expect(repaints, 0);
  });

  test('a key typed as a full-screen program quits waits for its echo', () {
    typeAndEcho('a');
    terminal.write('\x1b[?1049h');
    now += 6000;
    echo.userInput('q');
    echo.userInput('s');
    now += 50;
    terminal.write('\x1b[?1049l');

    echo.userInput('s');
    echo.userInput('\x7f');
    now += 50;
    terminal.write('s');

    expect(echo.cursor, isNull);
    expect(shown(), isEmpty);
  });

  test('a paste is not predicted', () {
    typeAndEcho('a');

    echo.userInput('x' * 100);

    expect(shown(), isEmpty);
  });

  test('turning it off clears what is shown', () {
    typeAndEcho('a');
    echo.userInput('b');

    echo.enabled = false;

    expect(shown(), isEmpty);
    expect(echo.cursor, isNull);
  });

  test('an Alt or Ctrl chord is not drawn as the letter', () {
    typeAndEcho('a');

    echo.userInput('\x1bb');
    echo.userInput('\x03');

    expect(shown(), isEmpty);
  });
}

String _char(int codePoint) =>
    codePoint == 0 ? ' ' : String.fromCharCode(codePoint);

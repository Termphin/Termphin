import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/services/terminal/terminal_search.dart';

Terminal _terminal(String output, {int cols = 20, int rows = 5}) {
  final terminal = Terminal(maxLines: 100)..resize(cols, rows);
  terminal.write(output);
  return terminal;
}

void main() {
  test('finds every occurrence, oldest first', () {
    final terminal = _terminal('error one\r\nok\r\nsecond error\r\n');

    expect(findInBuffer(terminal.buffer, 'error'), const [
      TerminalMatch(CellOffset(0, 0), CellOffset(5, 0)),
      TerminalMatch(CellOffset(7, 2), CellOffset(12, 2)),
    ]);
  });

  test('ignores case unless asked not to', () {
    final terminal = _terminal('Error\r\nerror\r\n');

    expect(findInBuffer(terminal.buffer, 'ERROR'), hasLength(2));
    expect(findInBuffer(terminal.buffer, 'Error', caseSensitive: true), const [
      TerminalMatch(CellOffset(0, 0), CellOffset(5, 0)),
    ]);
  });

  test('finds a word the terminal wrapped across the right edge', () {
    final terminal = _terminal('${'x' * 8}needle', cols: 10);

    expect(findInBuffer(terminal.buffer, 'needle'), const [
      TerminalMatch(CellOffset(8, 0), CellOffset(4, 1)),
    ]);
  });

  test('does not join two lines the program printed separately', () {
    final terminal = _terminal('nee\r\ndle\r\n');

    expect(findInBuffer(terminal.buffer, 'needle'), isEmpty);
  });

  test('maps past wide glyphs to the cells they cover', () {
    final terminal = _terminal('日本 ok\r\n');

    expect(findInBuffer(terminal.buffer, '本'), const [
      TerminalMatch(CellOffset(2, 0), CellOffset(4, 0)),
    ]);
    expect(findInBuffer(terminal.buffer, 'ok'), const [
      TerminalMatch(CellOffset(5, 0), CellOffset(7, 0)),
    ]);
  });

  test('matches do not overlap', () {
    final terminal = _terminal('aaaa\r\n');

    expect(findInBuffer(terminal.buffer, 'aa'), hasLength(2));
  });

  test('an empty query finds nothing', () {
    expect(findInBuffer(_terminal('abc').buffer, ''), isEmpty);
  });
}

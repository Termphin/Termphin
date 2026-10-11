import 'package:terminal_view/terminal_view.dart';

/// Keys after which the next thing typed starts a new command line: Enter,
/// Ctrl-C, Ctrl-D, Ctrl-L (redraws the prompt elsewhere), Ctrl-U, Ctrl-Z.
const _kLineResets = {0x0d, 0x0a, 0x03, 0x04, 0x0c, 0x15, 0x1a};

/// A prompt's last character followed by a space. Only a fallback: `echo a > b`
/// matches it too.
final _promptEnd = RegExp(r'[$#%>❯➜λ»›] ');

/// Reads what is typed at the shell prompt off the screen.
///
/// The terminal knows nothing of prompts, so where the input starts is taken
/// from where the cursor stood when the first key of a line was sent. That is
/// wrong when the key went out before the prompt was drawn, in which case the
/// start is found again by the shape of a prompt.
class CommandLineReader {
  CommandLineReader(this.terminal);

  final Terminal terminal;

  /// A command line was submitted, as it read just before Enter.
  void Function(String command)? onSubmit;

  BufferLine? _startLine;

  var _startCol = 0;

  /// What stood before [_startCol] when it was taken. Different now means the
  /// prompt was drawn after the key went out, and the start is not it.
  var _startPrefix = '';

  /// The first character typed at the start, when it was a character and not
  /// an escape sequence. Something else in that cell means the same thing.
  int? _startChar;

  var _awaitingStart = true;

  /// Feeds bytes that were just sent to the shell.
  void userInput(String data) {
    final isEscape = data.startsWith('\x1b');
    for (final rune in data.runes) {
      if (_kLineResets.contains(rune)) {
        if (rune == 0x0d || rune == 0x0a) {
          final command = read()?.trim();
          if (command != null && command.isNotEmpty) onSubmit?.call(command);
        }
        _awaitingStart = true;
        _startLine = null;
      } else if (_awaitingStart && rune >= 0x20 && rune != 0x7f) {
        final buffer = terminal.buffer;
        if (buffer.isAltBuffer) continue;
        _startLine = buffer.currentLine;
        _startCol = buffer.cursorX;
        _startPrefix = _cellsText(_startLine!, 0, _startCol);
        _startChar = isEscape ? null : rune;
        _awaitingStart = false;
      }
    }
  }

  /// The text between the prompt and the cursor, or null when there is no
  /// prompt to read - a full-screen program, or a line whose start is
  /// unknown (nothing typed on this line yet, so whatever is on screen is
  /// output). A long command wraps, so the rows it wrapped onto are read as
  /// one line.
  String? read() {
    final buffer = terminal.buffer;
    if (buffer.isAltBuffer || _awaitingStart) return null;

    final lines = buffer.lines;
    var first = buffer.absoluteCursorY;
    while (first > 0 && lines[first].isWrapped) {
      first--;
    }

    final text = StringBuffer();
    int? start;
    for (var i = first; i <= buffer.absoluteCursorY; i++) {
      final line = lines[i];
      final end = i == buffer.absoluteCursorY
          ? buffer.cursorX
          : buffer.viewWidth;
      if (identical(line, _startLine)) {
        final prefix = _cellsText(line, 0, _startCol);
        final char = _startCol < line.length ? line.getCodePoint(_startCol) : 0;
        if (prefix == _startPrefix &&
            (_startChar == null || char == 0 || char == _startChar)) {
          if (i == buffer.absoluteCursorY && _startCol > end) return null;
          start = text.length + prefix.length;
        }
      }
      text.write(_cellsText(line, 0, end));
    }

    final full = text.toString();
    if (start == null) {
      final match = _promptEnd.allMatches(full).lastOrNull;
      if (match == null) return null;
      start = match.end;
    }
    return full.substring(start).trimLeft();
  }

  /// Whether anything stands after the cursor, short of a gap of two blanks
  /// that ends the text - so a right-hand prompt does not count, while a
  /// suggestion the shell drew there, or the rest of a line being edited, does.
  bool textFollowsCursor() {
    final buffer = terminal.buffer;
    final line = buffer.currentLine;
    bool blank(int col) =>
        col >= line.length ||
        line.getCodePoint(col) == 0 ||
        line.getCodePoint(col) == 0x20;
    for (var col = buffer.cursorX; col < buffer.viewWidth; col++) {
      if (!blank(col)) return true;
      if (blank(col + 1)) return false;
    }
    return false;
  }

  /// The cells in `[from, to)` as text, blanks kept - `getText` drops trailing
  /// ones, and a trailing space is what says a new word has begun.
  static String _cellsText(BufferLine line, int from, int to) {
    final out = StringBuffer();
    for (var col = from; col < to; col++) {
      if (col >= line.length) {
        out.writeCharCode(0x20);
        continue;
      }
      final codePoint = line.getCodePoint(col);
      if (codePoint == 0) {
        if (col > 0 && line.getWidth(col - 1) == 2) continue;
        out.writeCharCode(0x20);
      } else {
        out.writeCharCode(codePoint);
      }
    }
    return out.toString();
  }
}

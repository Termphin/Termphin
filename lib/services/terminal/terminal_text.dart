import 'dart:math';

/// Turns raw terminal output into plain text fit for a read-only view.
///
/// Escape sequences are dropped rather than interpreted: a snippet run's
/// output is read, not driven, so colour, cursor moves and window-title
/// chatter are noise. Carriage returns and backspaces *are* honoured, because
/// progress output leans on them and ignoring them leaves a line of overwritten
/// garbage rather than the one value the command meant to show.
///
/// Of the control characters, only the two that carry layout are kept; the
/// rest (BEL, and anything else that slipped through) would only render as
/// tofu.
String stripAnsi(String input) {
  final out = StringBuffer();
  var index = 0;
  while (index < input.length) {
    final code = input.codeUnitAt(index);
    if (code == 0x1b) {
      index = _skipEscape(input, index);
      continue;
    }
    index++;
    if (code == 0x0a || code == 0x09 || code == 0x0d || code == 0x08) {
      out.writeCharCode(code);
    } else if (code >= 0x20 || code == 0x0b || code == 0x0c) {
      out.writeCharCode(code);
    }
  }
  return _applyOverwrites(out.toString());
}

/// Returns the index just past the escape sequence starting at [start].
///
/// A sequence cut short by the end of the buffer swallows the remainder: it
/// is the tail of a chunk that has not fully arrived, and printing its
/// fragments would put junk on screen for one frame.
///
/// A CSI sequence (`[`) ends at its final byte; a string sequence (`]`, `P`,
/// `X`, `^`, `_`) runs until BEL or ST (`ESC \`).
int _skipEscape(String input, int start) {
  final next = start + 1;
  if (next >= input.length) return input.length;
  switch (input[next]) {
    case '[':
      var index = next + 1;
      while (index < input.length) {
        final code = input.codeUnitAt(index);
        index++;
        if (code >= 0x40 && code <= 0x7e) return index;
      }
      return input.length;
    case ']':
    case 'P':
    case 'X':
    case '^':
    case '_':
      var index = next + 1;
      while (index < input.length) {
        final code = input.codeUnitAt(index);
        if (code == 0x07) return index + 1;
        if (code == 0x1b) {
          return index + 1 < input.length && input[index + 1] == '\\'
              ? index + 2
              : index + 1;
        }
        index++;
      }
      return input.length;
    default:
      return next + 1;
  }
}

/// Replays carriage returns and backspaces per line, so `\rDone` reads as
/// `Done` rather than as whatever it was painted over.
String _applyOverwrites(String text) {
  return text
      .split('\n')
      .map((line) {
        final buffer = <int>[];
        var column = 0;
        for (final code in line.codeUnits) {
          if (code == 0x0d) {
            column = 0;
          } else if (code == 0x08) {
            if (column > 0) column--;
          } else if (column < buffer.length) {
            buffer[column] = code;
            column++;
          } else {
            buffer.add(code);
            column++;
          }
        }
        return String.fromCharCodes(buffer);
      })
      .join('\n');
}

/// What a paste sends to the shell.
///
/// A shell that turned on bracketed paste gets the text wrapped, so it inserts
/// it rather than running each line as it arrives. Escape characters are
/// dropped from inside first: a pasted `ESC [201~` would close the bracket
/// early and run whatever follows it - text the server itself can put on the
/// clipboard with OSC 52. A shell that never asked gets the text as typed;
/// there is nothing to wrap it in that it would understand.
String pastePayload(String text, {required bool bracketed}) {
  if (!bracketed) return text;
  final inside = text.replaceAll(RegExp('[\x1b\x9b]'), '');
  return '\x1b[200~$inside\x1b[201~';
}

final _urlPattern = RegExp(r'https?://[^\s]+');
final _urlTrailingPunctuation = RegExp(r'[.,;:!?)\]>]+$');

/// Where the web addresses in [text] start and end (exclusive), trailing
/// punctuation left off. Only http and https - a scheme the server chose
/// (`javascript:`, `file:`, `intent:`) is text, never a link.
List<(int, int)> _spans(String text) {
  if (!text.contains('http')) return const [];
  return [
    for (final match in _urlPattern.allMatches(text))
      (
        match.start,
        match.start +
            match.group(0)!.replaceFirst(_urlTrailingPunctuation, '').length,
      ),
  ];
}

/// One row's part of a logical line, and the column its text starts at.
typedef LineSlice = ({int column, String text});

/// How far short of the right edge a full-screen program may stop a row it
/// broke itself: its own padding, a border, a scrollbar.
const _softWrapMargin = 10;

final _urlRun = RegExp(r"^[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+$");

/// Blank space and box drawing: what a full-screen program pads a row with.
bool _isPadding(int code) =>
    code <= 0x20 || code == 0xa0 || (code >= 0x2500 && code <= 0x257f);

int _contentStart(String row) {
  var index = 0;
  while (index < row.length && _isPadding(row.codeUnitAt(index))) {
    index++;
  }
  return index;
}

int _contentEnd(String row) {
  var index = row.length;
  while (index > 0 && _isPadding(row.codeUnitAt(index - 1))) {
    index--;
  }
  return index;
}

/// Whether row [next] carries on the line in row [prev].
///
/// The terminal says so for its own wrap ([wrapped]). A full-screen program
/// breaks a long address itself and pads both rows, so that is read off the
/// text: [prev] ends in an address, or the middle of one, close to the right
/// edge, and [next] goes straight on with more of it. Not when the terminal
/// wrapped onto [prev] ([prevWrapped]): such a program never writes past the
/// edge, so that row ends where a newline was printed.
bool continuesLine(
  String prev,
  String next, {
  required bool wrapped,
  required bool prevWrapped,
  required int width,
}) {
  if (wrapped) return true;
  if (prevWrapped) return false;
  final end = _contentEnd(prev);
  if (end == 0 || end < width - _softWrapMargin) return false;
  var tokenStart = end;
  while (tokenStart > 0 && !_isPadding(prev.codeUnitAt(tokenStart - 1))) {
    tokenStart--;
  }
  final token = prev.substring(tokenStart, end);
  if (!_urlRun.hasMatch(token)) return false;
  if (!token.contains('://') && tokenStart != _contentStart(prev)) return false;

  final start = _contentStart(next);
  var tokenEnd = start;
  while (tokenEnd < next.length && !_isPadding(next.codeUnitAt(tokenEnd))) {
    tokenEnd++;
  }
  final carried = next.substring(start, tokenEnd);
  return _urlRun.hasMatch(carried) && !carried.startsWith('http');
}

/// The slices of [rows] that make one logical line, given which rows the
/// terminal [wrapped]. Where a program broke the line itself, the padding
/// either side of the break is left out.
List<LineSlice> lineSlices(List<String> rows, List<bool> wrapped) {
  return [
    for (var i = 0; i < rows.length; i++)
      () {
        final start = i > 0 && !wrapped[i] ? _contentStart(rows[i]) : 0;
        final end = i + 1 < rows.length && !wrapped[i + 1]
            ? _contentEnd(rows[i])
            : rows[i].length;
        return (column: start, text: rows[i].substring(start, end));
      }(),
  ];
}

/// The web addresses in [line], as spans in each row's own columns. The
/// slices are read joined, so an address broken across rows is still one
/// link.
List<List<(int, int)>> linkSpans(List<LineSlice> line) {
  final spans = _spans(line.map((slice) => slice.text).join());
  final result = <List<(int, int)>>[];
  var sliceStart = 0;
  for (final slice in line) {
    final sliceEnd = sliceStart + slice.text.length;
    final shift = slice.column - sliceStart;
    result.add([
      for (final (start, end) in spans)
        if (start < sliceEnd && end > sliceStart)
          (max(start, sliceStart) + shift, min(end, sliceEnd) + shift),
    ]);
    sliceStart = sliceEnd;
  }
  return result;
}

/// The web address covering [column] of [row] in [line], if there is one.
///
/// Searched across the whole line, not the word under the tap: the
/// terminal's word boundaries break on `:`, `/` and `.`, so the word under a
/// finger inside a URL is never the URL.
String? linkAt(List<LineSlice> line, int row, int column) {
  final slice = line[row];
  if (column < slice.column) return null;
  final text = line.map((slice) => slice.text).join();
  final offset =
      line.take(row).fold(0, (sum, slice) => sum + slice.text.length) +
      column -
      slice.column;
  for (final (start, end) in _spans(text)) {
    if (offset >= start && offset < end) return text.substring(start, end);
  }
  return null;
}

final _terminalReport = RegExp(
  r'^\x1b(\[(M|<|I$|O$|\d+;\d+R$|[?>][\d;]*c$)|P|\])',
);

/// Whether [bytes] the terminal hands on are the user's own keys, rather than
/// the terminal answering the program: a mouse or focus report, or a reply to
/// a query (cursor position, device attributes, a DCS or OSC string). A tap
/// in a program that tracks the mouse sends a report, and that is not typing.
bool isTypedInput(List<int> bytes) {
  if (bytes.isEmpty) return false;
  if (bytes[0] != 0x1b || bytes.length == 1) return true;
  return !_terminalReport.hasMatch(String.fromCharCodes(bytes));
}

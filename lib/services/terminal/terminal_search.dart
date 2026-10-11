import 'package:terminal_view/core.dart';

/// One occurrence of the query in the buffer. [end] is exclusive, the same
/// convention the terminal's highlights and selection ranges use.
class TerminalMatch {
  const TerminalMatch(this.begin, this.end);

  final CellOffset begin;
  final CellOffset end;

  @override
  bool operator ==(Object other) =>
      other is TerminalMatch && other.begin == begin && other.end == end;

  @override
  int get hashCode => Object.hash(begin, end);

  @override
  String toString() => 'TerminalMatch($begin, $end)';
}

/// Every non-overlapping occurrence of [query] in [buffer], oldest first.
///
/// Rows the terminal soft-wrapped are joined back into the line the program
/// printed, so a word broken across the right edge is still found. Text is
/// rebuilt cell by cell rather than taken from [BufferLine.getText], which
/// drops wide-glyph halves and trailing blanks - the match has to map back to
/// exact cells to be highlighted. `rows`, `cols` and `widths` track, per
/// UTF-16 unit of the rebuilt text, the row, column and width of its cell. A
/// lowercased haystack is used for a case-insensitive search only when
/// lowering does not change its length - the few letters that do would
/// otherwise misalign those indexes.
List<TerminalMatch> findInBuffer(
  Buffer buffer,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];
  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TerminalMatch>[];
  final lines = buffer.lines;
  final text = StringBuffer();
  final rows = <int>[];
  final cols = <int>[];
  final widths = <int>[];

  var row = 0;
  while (row < lines.length) {
    text.clear();
    rows.clear();
    cols.clear();
    widths.clear();
    var last = row;
    while (true) {
      final line = lines[last];
      for (var x = 0; x < line.length; x++) {
        final codePoint = line.getCodePoint(x);
        final width = line.getWidth(x);
        if (codePoint == 0 && x > 0 && line.getWidth(x - 1) == 2) continue;
        final char = String.fromCharCode(codePoint == 0 ? 0x20 : codePoint);
        text.write(char);
        for (var unit = 0; unit < char.length; unit++) {
          rows.add(last);
          cols.add(x);
          widths.add(width < 1 ? 1 : width);
        }
      }
      if (last + 1 >= lines.length || !lines[last + 1].isWrapped) break;
      last++;
    }

    var haystack = text.toString();
    if (!caseSensitive) {
      final lowered = haystack.toLowerCase();
      if (lowered.length == haystack.length) haystack = lowered;
    }
    var start = haystack.indexOf(needle);
    while (start >= 0) {
      final end = start + needle.length - 1;
      matches.add(
        TerminalMatch(
          CellOffset(cols[start], rows[start]),
          CellOffset(cols[end] + widths[end], rows[end]),
        ),
      );
      start = haystack.indexOf(needle, start + needle.length);
    }
    row = last + 1;
  }
  return matches;
}

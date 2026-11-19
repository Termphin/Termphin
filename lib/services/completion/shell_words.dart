/// The word being typed at the end of a command line, read the way a POSIX
/// shell reads it: a blank inside quotes or after a backslash does not end
/// it, and the quotes and backslashes are not part of what the program gets.
class LastWord {
  const LastWord({
    required this.before,
    required this.raw,
    required this.plain,
    this.quote,
    this.rawBreak = 0,
    this.plainBreak = 0,
  });

  /// Everything before the word, as typed.
  final String before;

  /// The word as typed: `My\ Do`.
  final String raw;

  /// The word as the program would get it: `My Do`.
  final String plain;

  /// The quote left open at the end of the line, `'` or `"`.
  final String? quote;

  /// Where in [raw] the part after the word's last break begins. bash
  /// completes `--file=sr` as `sr` alone and answers `src/`.
  final int rawBreak;

  /// [rawBreak] in [plain].
  final int plainBreak;

  String get rawTail => raw.substring(rawBreak);

  String get plainTail => plain.substring(plainBreak);
}

bool _isBlank(String c) => c == ' ' || c == '\t';

/// The last word of [line]. A character of [breaks] outside quotes cuts the
/// word for completion, though not on the first word, the command itself.
///
/// Without [posix], as PowerShell takes it here: the last blank ends the
/// line before the word, and nothing is unquoted.
LastWord readLastWord(String line, {bool posix = true, String breaks = ''}) {
  if (!posix) {
    final at = line.lastIndexOf(RegExp(r'\s')) + 1;
    final word = line.substring(at);
    return LastWord(before: line.substring(0, at), raw: word, plain: word);
  }
  var start = 0;
  var firstWord = true;
  final plain = StringBuffer();
  String? quote;
  var escaped = false;
  var rawBreak = 0;
  var plainBreak = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (escaped) {
      escaped = false;
      if (quote == '"' && !r'$`"\'.contains(c)) plain.write(r'\');
      plain.write(c);
    } else if (quote == "'") {
      if (c == "'") {
        quote = null;
      } else {
        plain.write(c);
      }
    } else if (c == r'\') {
      escaped = true;
    } else if (quote == '"') {
      if (c == '"') {
        quote = null;
      } else {
        plain.write(c);
      }
    } else if (c == "'" || c == '"') {
      quote = c;
    } else if (_isBlank(c)) {
      if (i > start) firstWord = false;
      start = i + 1;
      plain.clear();
      rawBreak = 0;
      plainBreak = 0;
    } else {
      plain.write(c);
      if (!firstWord && breaks.contains(c)) {
        rawBreak = i + 1 - start;
        plainBreak = plain.length;
      }
    }
  }
  return LastWord(
    before: line.substring(0, start),
    raw: line.substring(start),
    plain: plain.toString(),
    quote: quote,
    rawBreak: rawBreak,
    plainBreak: plainBreak,
  );
}

/// [line] as bash hands it to a completion function in `COMP_WORDS`: words
/// as typed, each run of [breaks] a word of its own, and an empty last word
/// when the line ends in a blank.
List<String> completionWords(String line, {String breaks = '=:'}) {
  final words = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaped = false;
  var inBreak = false;
  var endsBlank = true;
  void flush() {
    if (current.isNotEmpty) words.add(current.toString());
    current.clear();
  }

  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    final literal = escaped || quote != null;
    if (!literal && _isBlank(c)) {
      flush();
      inBreak = false;
      endsBlank = true;
      continue;
    }
    endsBlank = false;
    final isBreak = !literal && breaks.contains(c);
    if (isBreak != inBreak) flush();
    inBreak = isBreak;
    current.write(c);
    if (escaped) {
      escaped = false;
    } else if (quote == "'") {
      if (c == "'") quote = null;
    } else if (c == r'\') {
      escaped = true;
    } else if (quote == '"') {
      if (c == '"') quote = null;
    } else if (c == "'" || c == '"') {
      quote = c;
    }
  }
  flush();
  if (endsBlank) words.add('');
  return words;
}

final _unquotedSpecial = RegExp(r'''[\s'"\\$`&|;<>()*?#!\[\]{}]''');
final _doubleQuotedSpecial = RegExp(r'[$`"\\]');

/// [text] written so the shell reads it back as it is, inside [quote] when
/// one is open.
String shellEscape(String text, {String? quote}) => switch (quote) {
  "'" => text.replaceAll("'", r"'\''"),
  '"' => text.replaceAllMapped(_doubleQuotedSpecial, (m) => '\\${m[0]}'),
  _ => text.replaceAllMapped(_unquotedSpecial, (m) => '\\${m[0]}'),
};

/// Whether [typed] is at most one edit - a character added, dropped,
/// changed, or two swapped - from how some [candidate] starts. Short words
/// are left out: two letters are one edit from too much.
bool isNearPrefix(String typed, String candidate) {
  if (typed.length < 3) return false;
  for (var k = typed.length - 1; k <= typed.length + 1; k++) {
    if (k < 1 || k > candidate.length) continue;
    if (_editDistanceAtMostOne(typed, candidate.substring(0, k))) return true;
  }
  return false;
}

/// Optimal string alignment distance of [a] and [b] is 0 or 1.
bool _editDistanceAtMostOne(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  if (a.length == b.length) {
    if (i == a.length) return true;
    if (a.substring(i + 1) == b.substring(i + 1)) return true;
    return i + 1 < a.length &&
        a[i] == b[i + 1] &&
        a[i + 1] == b[i] &&
        a.substring(i + 2) == b.substring(i + 2);
  }
  final (longer, shorter) = a.length > b.length ? (a, b) : (b, a);
  return longer.substring(i + 1) == shorter.substring(i);
}

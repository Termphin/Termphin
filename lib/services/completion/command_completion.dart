import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../settings/setting.dart';
import 'remote_completion.dart';
import 'shell_words.dart';

final Setting<bool> commandSuggestionsSetting = Setting.boolean(
  'command_suggestions_enabled',
  fallback: true,
);

/// The `whats_new.yaml` highlight that explains autocomplete, opened from
/// beside its setting.
const kAutocompleteExplainerId = 'command-suggestions';

enum SuggestionKind { history, word }

class CommandSuggestion {
  const CommandSuggestion({
    required this.label,
    required this.insert,
    required this.kind,
    this.erase = 0,
  });

  final String label;

  /// Characters deleted before [insert] is typed, when the suggestion
  /// rewrites what is on the line rather than adding to it: `te` becoming
  /// `./test`.
  final int erase;

  /// What is typed when the suggestion is taken: the rest of it, never the
  /// part already on the line.
  final String insert;

  final SuggestionKind kind;

  @override
  bool operator ==(Object other) =>
      other is CommandSuggestion &&
      other.label == label &&
      other.insert == insert &&
      other.kind == kind &&
      other.erase == erase;

  @override
  int get hashCode => Object.hash(label, insert, kind, erase);

  @override
  String toString() => '$kind($label -> "$insert")';
}

const _kLineMatches = 3;

/// Most rewrites offered for a word nothing starts with.
const _kTypoMatches = 3;

/// How a word is matched against a candidate. Each looser one is tried only
/// when the one before it found nothing, and rewrites the word rather than
/// finishing it.
enum _Match { exact, caseless, typo }

/// How words, names and paths read on a host: Windows ignores case, takes
/// either slash and is not unquoted here; bash completes a word after its
/// last `=` or `:` on its own.
class _Rules {
  _Rules(CompletionEngine engine)
    : windows = engine == CompletionEngine.powershell,
      breaks = engine == CompletionEngine.bash ? '=:' : '';

  final bool windows;

  final String breaks;

  LastWord lastWord(String line) =>
      readLastWord(line, posix: !windows, breaks: breaks);

  bool starts(String text, String prefix) => windows
      ? text.toLowerCase().startsWith(prefix.toLowerCase())
      : text.startsWith(prefix);

  bool matches(String candidate, String typed, _Match match) => switch (match) {
    _Match.exact => starts(candidate, typed),
    _Match.caseless => candidate.toLowerCase().startsWith(typed.toLowerCase()),
    _Match.typo => isNearPrefix(typed.toLowerCase(), candidate.toLowerCase()),
  };

  bool same(String a, String b) =>
      windows ? a.toLowerCase() == b.toLowerCase() : a == b;

  int lastSeparator(String word) => windows
      ? math.max(word.lastIndexOf('/'), word.lastIndexOf('\\'))
      : word.lastIndexOf('/');

  bool isDirectory(String path) =>
      path.endsWith('/') || (windows && path.endsWith('\\'));

  bool isRelative(String path) =>
      path.startsWith('./') || (windows && path.startsWith('.\\'));

  String escape(String text, {String? quote}) =>
      windows ? text : shellEscape(text, quote: quote);
}

/// The line the host's completion is asked about: everything up to the word
/// being typed, plus the part of that word up to its last slash or break.
/// Candidates for it are fetched once and narrowed locally as the rest of
/// the word is typed.
///
/// An option keeps its dash, or the host answers with files instead. The
/// first word is asked about as an argument to `ls`: command names are
/// already known locally, and what the host adds there is the files.
String completionQuery(
  String line, {
  CompletionEngine engine = CompletionEngine.bash,
}) {
  final rules = _Rules(engine);
  final word = rules.lastWord(line);
  final tail = word.rawTail;
  final dir =
      word.raw.substring(0, word.rawBreak) +
      tail.substring(0, rules.lastSeparator(tail) + 1);
  final option = tail.startsWith('--') ? '--' : '-';
  final query =
      word.before + (dir.isEmpty && tail.startsWith('-') ? option : dir);
  return word.before.trim().isEmpty ? 'ls ${query.trimLeft()}' : query;
}

/// Unique commands, most recent first - what zsh-autosuggestions and fish
/// do. Only one suggestion is shown, and the last thing run is the guess a
/// user can predict; a frequency score kept old habits on top.
///
/// What was run [here], in the directory the shell is in, goes before the
/// rest, as fish and atuin rank it: the same command line tends to be run
/// in the same place again.
List<String> rankHistory(List<String> history, {List<String> here = const []}) {
  final seen = <String>{};
  return [
    for (final command in here.reversed)
      if (seen.add(command)) command,
    for (final command in history.reversed)
      if (seen.add(command)) command,
  ];
}

/// Suggestions for [line], from the host's completion plus [data] and
/// [ranked] history.
///
/// Nothing on an empty line: a list of whatever is in the folder, unasked, is
/// noise. After a space, what follows the word before it is offered - `git `
/// offers its subcommands, `cd ` the folders; [words] is null after a word
/// the host does not know, so only history is left there. Otherwise,
/// commands actually used here are offered first, then files in the current
/// directory (run as `./name`, so the word is rewritten rather than
/// finished), then the rest of PATH - a program never run is a weaker guess
/// than a file the shell is standing next to. A directory is gone into and
/// `--opt=` takes its value, so neither is followed by a space.
///
/// Words are matched as the program gets them, unquoted, and what is typed
/// is quoted again the way the word already is. When nothing starts with the
/// word, it is matched regardless of case, then one typo away - a phone
/// keyboard capitalises and mistypes - and rewritten when taken.
List<CommandSuggestion> suggest(
  String line,
  HostCompletionData data, {
  List<String> ranked = const [],
  List<String>? words,
  int limit = 12,
}) {
  final rules = _Rules(data.engine);
  final result = <CommandSuggestion>[];
  final seen = <String>{};
  void add(String label, String insert, SuggestionKind kind, {int erase = 0}) {
    if (insert.isEmpty || !seen.add('$label\u0000$insert')) return;
    result.add(
      CommandSuggestion(label: label, insert: insert, kind: kind, erase: erase),
    );
  }

  if (line.trim().isEmpty) return result;
  final last = rules.lastWord(line);
  final word = last.plainTail;
  final looser = [
    _Match.exact,
    if (!rules.windows && last.quote == null) _Match.caseless,
    if (last.quote == null) _Match.typo,
  ];

  /// What finishes [candidate] after the word as typed: the rest of it, or
  /// all of it in place of the word when [match] is a loose one.
  void addWord(
    String candidate,
    _Match match, {
    String prefix = '',
    bool open = false,
    bool rewrite = false,
  }) {
    final close = open ? '' : '${last.quote ?? ''} ';
    if (match == _Match.exact && !rewrite) {
      final rest = candidate.substring(word.length);
      add(
        candidate,
        '${rules.escape(rest, quote: last.quote)}$close',
        SuggestionKind.word,
      );
    } else {
      add(
        '$prefix$candidate',
        '$prefix${rules.escape(candidate)}${open ? '' : ' '}',
        SuggestionKind.word,
        erase: rewrite ? last.raw.length : last.rawTail.length,
      );
    }
  }

  void addPaths() {
    if (words == null) return;
    for (final match in looser) {
      final before = result.length;
      for (final candidate in words) {
        if (rules.same(candidate, word) ||
            !rules.matches(candidate, word, match)) {
          continue;
        }
        final open = rules.isDirectory(candidate) || candidate.endsWith('=');
        addWord(candidate, match, open: open);
        if (result.length >= limit) return;
        if (match == _Match.typo && result.length >= before + _kTypoMatches) {
          return;
        }
      }
      if (result.length > before) return;
    }
  }

  for (final command in ranked) {
    if (result.length >= _kLineMatches) break;
    if (command.length > line.length &&
        !command.contains('\n') &&
        rules.starts(command, line)) {
      add(command, command.substring(line.length), SuggestionKind.history);
    }
  }

  if (last.before.trim().isNotEmpty || rules.lastSeparator(word) >= 0) {
    addPaths();
    return result.take(limit).toList();
  }

  final used = <String>{};
  for (final command in ranked) {
    used.add(splitFirstWord(command));
  }
  for (final match in looser) {
    final before = result.length;
    final typo = match == _Match.typo;
    final names = <String>{
      for (final name in used)
        if (!rules.same(name, word) && rules.matches(name, word, match)) name,
    };
    final cap = typo ? before + _kTypoMatches : limit;
    for (final name in names) {
      if (result.length >= cap) break;
      addWord(name, match);
    }

    if (!typo) {
      for (final candidate in words ?? const <String>[]) {
        if (!rules.matches(candidate, word, match) ||
            rules.isRelative(candidate)) {
          continue;
        }
        addWord(
          candidate,
          match,
          prefix: './',
          open: rules.isDirectory(candidate),
          rewrite: true,
        );
      }
    }

    final fromPath =
        data.commands
            .where(
              (c) =>
                  !rules.same(c, word) &&
                  !names.contains(c) &&
                  rules.matches(c, word, match),
            )
            .toList()
          ..sort((a, b) {
            final byLength = a.length.compareTo(b.length);
            return byLength != 0 ? byLength : a.compareTo(b);
          });
    for (final name in fromPath) {
      if (result.length >= cap) break;
      addWord(name, match);
    }
    if (result.length > before) break;
  }
  return result.take(limit).toList();
}

/// Whether the last word of [line] is itself something the host knows - a
/// command typed out in full, one of [words] exactly (a directory with or
/// without its slash), or an option. Only after such a word is the next one
/// worth suggesting: a word typed short of what was offered for it, and left
/// there, is not a command whose arguments anyone can guess.
bool isKnownWord(
  String line,
  HostCompletionData data, {
  List<String> ranked = const [],
  List<String>? words,
}) {
  final rules = _Rules(data.engine);
  final last = rules.lastWord(line);
  final word = last.plainTail;
  if (last.plain.isEmpty) return false;
  if (last.plain.startsWith('-')) return true;
  bool matches(String w) =>
      rules.same(w, word) ||
      (rules.isDirectory(w) && rules.same(w.substring(0, w.length - 1), word));
  if (words != null && words.any(matches)) return true;
  if (last.before.trim().isNotEmpty) return false;
  return data.commands.any((c) => rules.same(c, word)) ||
      ranked.any((c) => rules.same(splitFirstWord(c), word));
}

String splitFirstWord(String command) {
  final trimmed = command.trimLeft();
  final space = trimmed.indexOf(RegExp(r'\s'));
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

/// Per host: what the probe found plus what was typed since, read again
/// once it is [freshFor] old so a program installed since shows up. A failed
/// probe is cached as empty for [retryAfter] rather than retried on every
/// keystroke.
class HostCompletionCache {
  static final _hosts = <String, _CacheEntry>{};

  static const freshFor = Duration(hours: 1);

  static const retryAfter = Duration(minutes: 1);

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// The host's data. The same future while it is fresh, a new one once it
  /// is not; the new one keeps what the old one remembered.
  static Future<HostCompletionData> load(
    String hostKey,
    Future<Uint8List> Function(String command) run, {
    bool windows = false,
  }) {
    final entry = _hosts[hostKey];
    if (entry != null && !entry.isStale(now())) return entry.data;
    final previous = entry?.data;
    final next = _CacheEntry();
    next.data = () async {
      HostCompletionData data;
      try {
        final output = await run(
          windows ? powerShellProbeCommand() : probeCommand(),
        ).timeout(const Duration(seconds: 15));
        data = parseProbe(output);
      } catch (_) {
        data = HostCompletionData.empty;
        next.failed = true;
      }
      if (previous != null) data.carryOver(await previous);
      next.loadedAt = now();
      return data;
    }();
    _hosts[hostKey] = next;
    return next.data;
  }

  @visibleForTesting
  static void clear() => _hosts.clear();
}

class _CacheEntry {
  late final Future<HostCompletionData> data;

  /// Null while the probe is running: a running one is never stale.
  DateTime? loadedAt;

  var failed = false;

  bool isStale(DateTime now) {
    final at = loadedAt;
    if (at == null) return false;
    return now.difference(at) >=
        (failed
            ? HostCompletionCache.retryAfter
            : HostCompletionCache.freshFor);
  }
}

/// Suggestions for one session's command line, kept in [suggestions].
///
/// Fed the line on every change; history and command names answer at once,
/// the host's own completion after a pause and one round trip - no pause
/// once a word is ended or a directory entered, when what to ask is already
/// certain.
class CommandCompletion {
  CommandCompletion({
    required this.hostKey,
    required this.run,
    required this.windows,
    required this.location,
  });

  final String hostKey;

  final Future<Uint8List> Function(String command) run;

  /// Whether the host is Windows, where PowerShell answers instead of sh.
  final bool Function() windows;

  /// Where the shell is: on Unix the file the agent records it in, relative
  /// to home; on Windows the directory itself, as the prompt last reported.
  final String? Function() location;

  final suggestions = ValueNotifier<List<CommandSuggestion>>(const []);

  static const _fetchDelay = Duration(milliseconds: 200);

  /// Host answers kept for one line, so going back over a word asks nothing
  /// again.
  static const _kAnswersKept = 16;

  Future<HostCompletionData>? _loading;
  HostCompletionData? _data;
  List<String> _ranked = const [];
  Object? _rankedFor;

  String? _line;
  final _answers = <String, List<String>>{};
  String? _pendingQuery;
  Timer? _fetchTimer;
  var _disposed = false;

  /// The directory the host last said it completed in, which is where a
  /// command submitted now runs.
  String? _directory;

  /// The last line published that did not end in a space, and whether its
  /// last word was known not to be a command, file or option the host knows.
  /// After such a word and a space, no files or arguments are offered: what
  /// follows an unknown word is a guess. History that matches the line still
  /// is.
  String? _lastWordLine;
  var _lastWordUnknown = false;

  /// Feeds a new line to publish suggestions for.
  ///
  /// A new line may be in another directory, so a blank or missing one drops
  /// whatever was fetched for the last one.
  void update(String? line) {
    if (line == _line) return;
    _line = line;
    if (line == null || line.trim().isEmpty) _answers.clear();
    if (line == null) {
      _fetchTimer?.cancel();
      suggestions.value = const [];
      return;
    }
    _ensureLoaded();
    _publish();
    _fetchTimer?.cancel();
    _fetchTimer = Timer(
      _endsWord(line) ? Duration.zero : _fetchDelay,
      _fetchWords,
    );
  }

  void remember(String command) {
    final directory = windows() ? location() : _directory;
    _ensureLoaded().then((data) {
      data.remember(command, directory: directory);
      _rankedFor = null;
    });
  }

  /// The cache's data for the host, asked again on every call so data read
  /// again once stale replaces what this session holds.
  Future<HostCompletionData> _ensureLoaded() {
    final loading = HostCompletionCache.load(hostKey, run, windows: windows());
    if (identical(loading, _loading)) return loading;
    _loading = loading;
    loading.then((data) {
      if (!identical(loading, _loading)) return;
      _data = data;
      _rankedFor = null;
      if (!_disposed) _publish();
    });
    return loading;
  }

  bool _endsWord(String line) =>
      line.endsWith(' ') ||
      line.endsWith('/') ||
      line.endsWith('=') ||
      (windows() && line.endsWith('\\'));

  /// Recomputes and republishes [suggestions] for the current line.
  ///
  /// Whether the last word is unknown is only settled once it is certain:
  /// the host's data has been read, and its answer for this word is in, or
  /// none is coming. A space typed before then is not held against the word.
  void _publish() {
    final line = _line;
    if (line == null || _disposed) return;
    final data = _data ?? HostCompletionData.empty;
    final directory = windows() ? location() : _directory;
    final rankedFor = (data, data.history.length, directory);
    if (rankedFor != _rankedFor) {
      _ranked = rankHistory(data.history, here: data.ranIn(directory));
      _rankedFor = rankedFor;
    }
    final words = _answers[_query(line, data)];
    final next = suggest(
      line,
      data,
      ranked: _ranked,
      words: _afterUnknownWord(line) ? null : words,
    );
    if (!line.endsWith(' ')) {
      _lastWordLine = line;
      final settled =
          _data != null &&
          (data.engine == CompletionEngine.none || words != null);
      _lastWordUnknown =
          settled && !isKnownWord(line, data, ranked: _ranked, words: words);
    }
    if (!listEquals(next, suggestions.value)) suggestions.value = next;
  }

  bool _afterUnknownWord(String line) =>
      _lastWordUnknown &&
      line.endsWith(' ') &&
      line.trimRight() == _lastWordLine;

  /// Asks the host for completions of the current word, once [_fetchDelay]
  /// after the last [update]. A failed or overlong request is just not
  /// offered.
  Future<void> _fetchWords() async {
    final line = _line;
    final data = _data;
    if (line == null || data == null) return;
    if (data.engine == CompletionEngine.none) return;
    if (_afterUnknownWord(line)) return;
    final query = _query(line, data);
    if (_answers.containsKey(query) || query == _pendingQuery) return;
    _pendingQuery = query;
    try {
      final output = await run(
        data.engine == CompletionEngine.powershell
            ? completeCommand(data.engine, query, directory: location())
            : completeCommand(
                data.engine,
                query,
                cwdFile: location(),
                bashCompletionPath: data.bashCompletionPath,
              ),
      ).timeout(const Duration(seconds: 6));
      if (_disposed || _pendingQuery != query) return;
      _directory = completionDirectory(output) ?? _directory;
      _answers.remove(query);
      _answers[query] = parseCandidates(output);
      while (_answers.length > _kAnswersKept) {
        _answers.remove(_answers.keys.first);
      }
      _publish();
    } catch (_) {
    } finally {
      if (_pendingQuery == query) _pendingQuery = null;
    }
  }

  static String _query(String line, HostCompletionData data) =>
      completionQuery(line, engine: data.engine);

  void dispose() {
    _disposed = true;
    _fetchTimer?.cancel();
    suggestions.dispose();
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../settings/setting.dart';
import 'remote_completion.dart';

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

/// [line] split before its last word.
({String before, String word}) splitLastWord(String line) {
  final at = line.lastIndexOf(RegExp(r'\s')) + 1;
  return (before: line.substring(0, at), word: line.substring(at));
}

/// How names and paths compare on a host: Windows ignores case and takes
/// either slash.
class _Rules {
  const _Rules(this.windows);

  final bool windows;

  bool starts(String text, String prefix) => windows
      ? text.toLowerCase().startsWith(prefix.toLowerCase())
      : text.startsWith(prefix);

  bool same(String a, String b) =>
      windows ? a.toLowerCase() == b.toLowerCase() : a == b;

  int lastSeparator(String word) => windows
      ? math.max(word.lastIndexOf('/'), word.lastIndexOf('\\'))
      : word.lastIndexOf('/');

  bool isDirectory(String path) =>
      path.endsWith('/') || (windows && path.endsWith('\\'));

  bool isRelative(String path) =>
      path.startsWith('./') || (windows && path.startsWith('.\\'));
}

/// The line the host's completion is asked about: everything up to the word
/// being typed, plus the directory part of that word. Candidates for it are
/// fetched once and narrowed locally as the rest of the word is typed.
///
/// An option keeps its dash, or the host answers with files instead. The
/// first word is asked about as an argument to `ls`: command names are
/// already known locally, and what the host adds there is the files.
String completionQuery(String line, {bool windows = false}) {
  final (:before, :word) = splitLastWord(line);
  final dir = word.substring(0, _Rules(windows).lastSeparator(word) + 1);
  final option = word.startsWith('--') ? '--' : '-';
  final query = before + (dir.isEmpty && word.startsWith('-') ? option : dir);
  return before.trim().isEmpty ? 'ls ${query.trimLeft()}' : query;
}

/// Unique commands, most recent first - what zsh-autosuggestions and fish
/// do. Only one suggestion is shown, and the last thing run is the guess a
/// user can predict; a frequency score kept old habits on top.
List<String> rankHistory(List<String> history) {
  final seen = <String>{};
  return [
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
List<CommandSuggestion> suggest(
  String line,
  HostCompletionData data, {
  List<String> ranked = const [],
  List<String>? words,
  int limit = 12,
}) {
  final rules = _Rules(data.engine == CompletionEngine.powershell);
  final result = <CommandSuggestion>[];
  final seen = <String>{};
  void add(String label, String insert, SuggestionKind kind, {int erase = 0}) {
    if (insert.isEmpty || !seen.add('$label\u0000$insert')) return;
    result.add(
      CommandSuggestion(label: label, insert: insert, kind: kind, erase: erase),
    );
  }

  void addPaths(String word) {
    if (words == null) return;
    for (final candidate in words) {
      if (rules.same(candidate, word) || !rules.starts(candidate, word)) {
        continue;
      }
      final rest = candidate.substring(word.length);
      final open = rules.isDirectory(candidate) || candidate.endsWith('=');
      add(candidate, open ? rest : '$rest ', SuggestionKind.word);
      if (result.length >= limit) break;
    }
  }

  final (:before, :word) = splitLastWord(line);
  if (line.trim().isEmpty) return result;

  for (final command in ranked) {
    if (result.length >= _kLineMatches) break;
    if (command.length > line.length && rules.starts(command, line)) {
      add(command, command.substring(line.length), SuggestionKind.history);
    }
  }

  if (before.trim().isNotEmpty) {
    addPaths(word);
    return result.take(limit).toList();
  }
  if (rules.lastSeparator(word) >= 0) {
    addPaths(word);
    return result.take(limit).toList();
  }

  final used = <String>{};
  for (final command in ranked) {
    final name = splitFirstWord(command);
    if (rules.starts(name, word)) used.add(name);
  }
  for (final name in used) {
    if (!rules.same(name, word)) {
      add(name, '${name.substring(word.length)} ', SuggestionKind.word);
    }
  }

  for (final candidate in words ?? const <String>[]) {
    if (!rules.starts(candidate, word) || rules.isRelative(candidate)) continue;
    final path = './$candidate';
    add(
      path,
      rules.isDirectory(candidate) ? path : '$path ',
      SuggestionKind.word,
      erase: word.length,
    );
  }

  final fromPath =
      data.commands
          .where(
            (c) =>
                rules.starts(c, word) &&
                !rules.same(c, word) &&
                !used.contains(c),
          )
          .toList()
        ..sort((a, b) {
          final byLength = a.length.compareTo(b.length);
          return byLength != 0 ? byLength : a.compareTo(b);
        });
  for (final name in fromPath) {
    if (result.length >= limit) break;
    add(name, '${name.substring(word.length)} ', SuggestionKind.word);
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
  final rules = _Rules(data.engine == CompletionEngine.powershell);
  final (:before, :word) = splitLastWord(line);
  if (word.isEmpty) return false;
  if (word.startsWith('-')) return true;
  bool matches(String w) =>
      rules.same(w, word) ||
      (rules.isDirectory(w) && rules.same(w.substring(0, w.length - 1), word));
  if (words != null && words.any(matches)) return true;
  if (before.trim().isNotEmpty) return false;
  return data.commands.any((c) => rules.same(c, word)) ||
      ranked.any((c) => rules.same(splitFirstWord(c), word));
}

String splitFirstWord(String command) {
  final trimmed = command.trimLeft();
  final space = trimmed.indexOf(RegExp(r'\s'));
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

/// Per host, for the life of the process: what the probe found plus what was
/// typed since. A failed probe is cached as empty rather than retried on every
/// keystroke.
class HostCompletionCache {
  static final _hosts = <String, Future<HostCompletionData>>{};

  static Future<HostCompletionData> load(
    String hostKey,
    Future<Uint8List> Function(String command) run, {
    bool windows = false,
  }) => _hosts.putIfAbsent(hostKey, () async {
    try {
      final output = await run(
        windows ? powerShellProbeCommand() : probeCommand(),
      ).timeout(const Duration(seconds: 15));
      return parseProbe(output);
    } catch (_) {
      return HostCompletionData.empty;
    }
  });

  @visibleForTesting
  static void clear() => _hosts.clear();
}

/// Suggestions for one session's command line, kept in [suggestions].
///
/// Fed the line on every change; history and command names answer at once,
/// the host's own completion after a pause and one round trip.
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

  Future<HostCompletionData>? _loading;
  HostCompletionData? _data;
  List<String> _ranked = const [];
  int _rankedFor = -1;

  String? _line;
  String? _wordsQuery;
  List<String>? _words;
  String? _pendingQuery;
  Timer? _fetchTimer;
  var _disposed = false;

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
  /// whatever directory listing was fetched for the last one.
  void update(String? line) {
    if (line == _line) return;
    _line = line;
    if (line == null || line.trim().isEmpty) {
      _wordsQuery = null;
      _words = null;
    }
    if (line == null) {
      _fetchTimer?.cancel();
      suggestions.value = const [];
      return;
    }
    _ensureLoaded();
    _publish();
    _fetchTimer?.cancel();
    _fetchTimer = Timer(_fetchDelay, _fetchWords);
  }

  void remember(String command) {
    _ensureLoaded().then((data) {
      data.remember(command);
      _rankedFor = -1;
    });
  }

  Future<HostCompletionData> _ensureLoaded() => _loading ??=
      HostCompletionCache.load(hostKey, run, windows: windows()).then((data) {
        _data = data;
        if (!_disposed) _publish();
        return data;
      });

  /// Recomputes and republishes [suggestions] for the current line.
  ///
  /// Whether the last word is unknown is only settled once it is certain:
  /// the host's data has been read, and its answer for this word is in, or
  /// none is coming. A space typed before then is not held against the word.
  void _publish() {
    final line = _line;
    if (line == null || _disposed) return;
    final data = _data ?? HostCompletionData.empty;
    if (_rankedFor != data.history.length) {
      _ranked = rankHistory(data.history);
      _rankedFor = data.history.length;
    }
    final words = _wordsQuery == _query(line, data) ? _words : null;
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
    if (query == _wordsQuery || query == _pendingQuery) return;
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
      _wordsQuery = query;
      _words = parseCandidates(output);
      _publish();
    } catch (_) {
    } finally {
      if (_pendingQuery == query) _pendingQuery = null;
    }
  }

  static String _query(String line, HostCompletionData data) => completionQuery(
    line,
    windows: data.engine == CompletionEngine.powershell,
  );

  void dispose() {
    _disposed = true;
    _fetchTimer?.cancel();
    suggestions.dispose();
  }
}

import 'dart:convert';

import '../services/storage/group_storage.dart';

/// Regex that finds {{placeholder}} tokens in a snippet command. Argument
/// names are derived from these tokens directly - there is no separate
/// argument-definition model to keep in sync.
final _placeholderRe = RegExp(r'\{\{(\w+)\}\}');

/// A saved command a user can insert or run in a terminal session.
///
/// Kept deliberately flat: no per-language templating and no execution-mode
/// switch. A snippet always runs when chosen; everything else (whether the
/// body needs staging as a script, which remote shell dialect to use) is
/// decided at run time from the session's actual [RemoteShellType].
class Snippet {
  Snippet({
    required this.id,
    required this.name,
    required this.command,
    required this.createdAt,
    DateTime? updatedAt,
    this.group = GroupStorage.defaultGroup,
    this.defaults = const {},
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String name;
  final String command;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String group;

  /// Value each `{{token}}` starts out with when the snippet is run, keyed by
  /// placeholder name. Only what the user filled in - a placeholder with no
  /// entry simply starts blank, and an entry whose token has since left the
  /// command is ignored rather than pruned, so editing the command back
  /// restores it.
  final Map<String, String> defaults;

  /// Distinct `{{token}}` names found in [command], in first-seen order.
  List<String> get placeholders => placeholdersIn(command);

  /// The same, for command text that has no snippet yet - the editor reads
  /// its field through this while it is still being typed.
  static List<String> placeholdersIn(String command) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final match in _placeholderRe.allMatches(command)) {
      final name = match.group(1)!;
      if (seen.add(name)) ordered.add(name);
    }
    return ordered;
  }

  /// [command] with every `{{token}}` replaced by [values][token] (blank if
  /// missing).
  String interpolate(Map<String, String> values) {
    return command.replaceAllMapped(_placeholderRe, (match) {
      return values[match.group(1)!] ?? '';
    });
  }

  /// The default for [name], or an empty string when it has none.
  String defaultFor(String name) => defaults[name] ?? '';

  Snippet copyWith({
    String? name,
    String? command,
    DateTime? updatedAt,
    String? group,
    Map<String, String>? defaults,
  }) {
    return Snippet(
      id: id,
      name: name ?? this.name,
      command: command ?? this.command,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      group: group ?? this.group,
      defaults: defaults ?? this.defaults,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'group': group,
    'defaults': defaults,
  };

  /// `autoRun` was dropped: snippets always run. Older records still carry
  /// the field and are read without it.
  factory Snippet.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final group =
        json['group'] as String? ??
        (json['tags'] as List<dynamic>?)?.cast<String>().firstOrNull ??
        GroupStorage.defaultGroup;
    return Snippet(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      createdAt: createdAt,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : createdAt,
      group: group,
      defaults:
          (json['defaults'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value as String),
          ) ??
          const {},
    );
  }

  String encode() => jsonEncode(toJson());

  static Snippet decode(String raw) =>
      Snippet.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  static List<String> encodeList(List<Snippet> snippets) =>
      snippets.map((s) => s.encode()).toList();

  static List<Snippet> decodeList(List<String> rawSnippets) =>
      rawSnippets.map(Snippet.decode).toList();
}

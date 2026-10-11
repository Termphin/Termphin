import 'package:shared_preferences/shared_preferences.dart';

import '../../models/snippet.dart';
import 'write_queue.dart';

class SnippetStorage {
  static const String _snippetsKey = 'snippets';

  /// See [ProfileStorage] - shared across instances because the thing being
  /// serialised is the SharedPreferences key, not the object holding it.
  static final WriteQueue _writes = WriteQueue();

  /// Snippets, most recently updated first. An entry that fails to decode is
  /// skipped instead, so the rest of the snippets are still available.
  Future<List<Snippet>> loadSnippets() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_snippetsKey) ?? <String>[];
    final snippets = <Snippet>[];
    for (final entry in raw) {
      try {
        snippets.add(Snippet.decode(entry));
      } catch (_) {}
    }
    snippets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return snippets;
  }

  Future<void> saveSnippets(List<Snippet> snippets) async {
    final preferences = await SharedPreferences.getInstance();
    final sorted = [...snippets]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await preferences.setStringList(_snippetsKey, Snippet.encodeList(sorted));
  }

  Future<void> addSnippet(Snippet snippet) => _writes.run(() async {
    final snippets = await loadSnippets();
    snippets.add(snippet);
    await saveSnippets(snippets);
  });

  Future<void> updateSnippet(Snippet snippet) => _writes.run(() async {
    final snippets = await loadSnippets();
    final index = snippets.indexWhere((item) => item.id == snippet.id);
    if (index == -1) {
      throw StateError('Snippet not found.');
    }
    snippets[index] = snippet;
    await saveSnippets(snippets);
  });

  Future<void> deleteSnippet(String snippetId) => _writes.run(() async {
    final snippets = await loadSnippets();
    snippets.removeWhere((snippet) => snippet.id == snippetId);
    await saveSnippets(snippets);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/snippet.dart';
import '../services/storage/group_storage.dart';
import '../services/storage/snippet_storage.dart';

final snippetStorageProvider = Provider<SnippetStorage>((ref) {
  return SnippetStorage();
});

final snippetsProvider = NotifierProvider<SnippetsNotifier, List<Snippet>>(
  SnippetsNotifier.new,
);

class SnippetsNotifier extends Notifier<List<Snippet>> {
  late final SnippetStorage _storage;
  static const Uuid _uuid = Uuid();

  @override
  List<Snippet> build() {
    _storage = ref.read(snippetStorageProvider);
    loadSnippets();
    return const [];
  }

  Future<void> loadSnippets() async {
    final snippets = await _storage.loadSnippets();
    if (!ref.mounted) return;
    state = snippets;
  }

  Future<void> addSnippet({
    required String name,
    required String command,
    String group = GroupStorage.defaultGroup,
    Map<String, String> defaults = const {},
  }) async {
    final snippet = Snippet(
      id: _uuid.v4(),
      name: name.trim(),
      command: command,
      createdAt: DateTime.now(),
      group: group,
      defaults: defaults,
    );
    await _storage.addSnippet(snippet);
    await loadSnippets();
  }

  /// Saves a copy of [snippet] under [name], carrying everything else across.
  Future<void> duplicateSnippet(Snippet snippet, {required String name}) async {
    await addSnippet(
      name: name,
      command: snippet.command,
      group: snippet.group,
      defaults: snippet.defaults,
    );
  }

  Future<void> updateSnippet(
    Snippet snippet, {
    required String name,
    required String command,
    String? group,
    Map<String, String>? defaults,
  }) async {
    final updated = snippet.copyWith(
      name: name.trim(),
      command: command,
      updatedAt: DateTime.now(),
      group: group,
      defaults: defaults,
    );
    await _storage.updateSnippet(updated);
    await loadSnippets();
  }

  Future<void> deleteSnippet(String snippetId) async {
    await _storage.deleteSnippet(snippetId);
    await loadSnippets();
  }
}

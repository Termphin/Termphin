import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/secret_cipher.dart';

const _storeKey = 'assistant_memory';
const _storeAad = 'assistant_memory';

/// What Phin remembers about each server, by profile id: short facts it
/// saved - which service runs the app, where its configuration lives - so
/// a later conversation does not have to look them up again.
///
/// Kept on this device only, sealed like the rest of the app's secrets.
/// The notes hold real names; they are hidden behind placeholders like
/// everything else on their way to the model.
class AssistantMemoryStore extends ChangeNotifier {
  AssistantMemoryStore({SecretCipher? cipher})
    : _cipher = cipher ?? SecretCipher.instance;

  /// Notes kept per server; the oldest goes when a new one would pass it.
  static const maxNotes = 30;

  /// Longest note, in characters.
  static const maxLength = 300;

  final SecretCipher _cipher;
  Map<String, List<String>>? _notes;

  Future<List<String>> notesFor(String profileId) async =>
      List.unmodifiable((await _load())[profileId] ?? const <String>[]);

  /// Every server with notes, by profile id.
  Future<Map<String, List<String>>> all() async => {
    for (final entry in (await _load()).entries)
      if (entry.value.isNotEmpty) entry.key: List.unmodifiable(entry.value),
  };

  /// Saves [note] for [profileId]. Returns false when it adds nothing - an
  /// empty note, or one already there.
  Future<bool> add(String profileId, String note) async {
    final clean = note.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return false;
    final trimmed = clean.length > maxLength
        ? clean.substring(0, maxLength)
        : clean;
    final notes = (await _load()).putIfAbsent(profileId, () => []);
    if (notes.any((n) => n.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    notes.add(trimmed);
    while (notes.length > maxNotes) {
      notes.removeAt(0);
    }
    await _save();
    return true;
  }

  Future<void> remove(String profileId, String note) async {
    final notes = (await _load())[profileId];
    if (notes == null || !notes.remove(note)) return;
    await _save();
  }

  Future<void> forget(String profileId) async {
    if ((await _load()).remove(profileId) == null) return;
    await _save();
  }

  Future<void> forgetAll() async {
    (await _load()).clear();
    await _save();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    final notes = _notes!;
    if (notes.values.every((n) => n.isEmpty)) {
      await preferences.remove(_storeKey);
    } else {
      await preferences.setString(
        _storeKey,
        await _cipher.seal(jsonEncode(notes), aad: _storeAad),
      );
    }
    notifyListeners();
  }

  Future<Map<String, List<String>>> _load() async {
    final cached = _notes;
    if (cached != null) return cached;
    final notes = <String, List<String>>{};
    final stored = (await SharedPreferences.getInstance()).getString(_storeKey);
    if (stored != null) {
      final opened = await _cipher.open(stored, aad: _storeAad);
      if (opened != null) {
        try {
          final decoded = jsonDecode(opened) as Map<String, dynamic>;
          for (final entry in decoded.entries) {
            notes[entry.key] = [
              for (final note in entry.value as List) '$note',
            ];
          }
        } on FormatException {
          notes.clear();
        }
      }
    }
    return _notes = notes;
  }

  @visibleForTesting
  void forgetCache() => _notes = null;
}

/// What Phin remembers, on this device.
final assistantMemory = AssistantMemoryStore();

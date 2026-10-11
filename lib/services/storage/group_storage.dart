import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profile_group.dart';
import '../../utils/group_match.dart';
import 'profile_storage.dart';
import 'snippet_storage.dart';
import 'ssh_key_storage.dart';
import 'write_queue.dart';

class GroupStorage {
  GroupStorage({
    ProfileStorage? profiles,
    SshKeyStorage? keys,
    SnippetStorage? snippets,
  }) : _profiles = profiles ?? ProfileStorage(),
       _keys = keys ?? SshKeyStorage(),
       _snippets = snippets ?? SnippetStorage();

  static const String defaultGroup = 'General';
  static const String _groupsKey = 'app_groups';
  static const String migratedKey = 'app_groups_migrated_v1';

  static final WriteQueue _writes = WriteQueue();

  final ProfileStorage _profiles;
  final SshKeyStorage _keys;
  final SnippetStorage _snippets;

  /// Seeds the groups list the first time it is read.
  ///
  /// Records can already name a group the stored list never heard of - one
  /// read back off a legacy `tags` entry, or restored from a backup.
  /// Adopting them here, once, is what stops a record pointing at a group
  /// that is not on the list. It is a seed, not a merge: after this the list
  /// is only ever what was saved to it.
  Future<void> _ensureMigrated(SharedPreferences preferences) async {
    if (preferences.getBool(migratedKey) ?? false) return;
    if (preferences.containsKey(_groupsKey)) {
      await preferences.setBool(migratedKey, true);
      return;
    }

    final initialGroups = <ProfileGroup>[];
    final legacyGroups = preferences.getStringList('profile_groups');
    if (legacyGroups != null && legacyGroups.isNotEmpty) {
      for (final name in legacyGroups) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty &&
            !initialGroups.any(
              (g) => g.name.toLowerCase() == trimmed.toLowerCase(),
            )) {
          initialGroups.add(ProfileGroup(name: trimmed));
        }
      }
    }

    for (final name in [
      for (final p in await _profiles.loadProfiles()) p.group,
      for (final k in await _keys.loadKeys()) k.group,
      for (final s in await _snippets.loadSnippets()) s.group,
    ]) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      if (initialGroups.any(
        (g) => g.name.toLowerCase() == trimmed.toLowerCase(),
      )) {
        continue;
      }
      initialGroups.add(ProfileGroup(name: trimmed));
    }

    if (!initialGroups.any(
      (g) => g.name.toLowerCase() == defaultGroup.toLowerCase(),
    )) {
      initialGroups.insert(0, const ProfileGroup(name: defaultGroup));
    }

    await saveGroups(initialGroups);
    await preferences.setBool(migratedKey, true);
  }

  /// Stored groups, with [defaultGroup] guaranteed to be present.
  ///
  /// A persisted entry that fails to decode is skipped rather than failing
  /// the whole read, so the rest of the groups are still available.
  Future<List<ProfileGroup>> loadGroups() async {
    final preferences = await SharedPreferences.getInstance();
    await _ensureMigrated(preferences);

    final rawList = preferences.getStringList(_groupsKey) ?? <String>[];
    final groups = <ProfileGroup>[];
    for (final raw in rawList) {
      try {
        groups.add(ProfileGroup.decode(raw));
      } catch (_) {}
    }

    final generalIndex = groups.indexWhere(
      (g) => g.name.toLowerCase() == defaultGroup.toLowerCase(),
    );
    if (generalIndex == -1) {
      groups.add(const ProfileGroup(name: defaultGroup));
    } else {
      final general = groups[generalIndex];
      if (general.name != defaultGroup) {
        groups[generalIndex] = ProfileGroup(
          name: defaultGroup,
          colorHex: general.colorHex,
        );
      }
    }

    return groups;
  }

  /// Persists [groups]. Case-insensitively deduplicates and ensures [defaultGroup]
  /// is present. Rejects case-insensitive duplicates with an [ArgumentError].
  Future<void> saveGroups(List<ProfileGroup> groups) async {
    final preferences = await SharedPreferences.getInstance();

    final seen = <String>{};
    for (final g in groups) {
      final trimmed = g.name.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (!seen.add(lower)) {
        throw ArgumentError('Duplicate group: ${g.name}');
      }
    }

    final sanitized = <ProfileGroup>[];
    var hasGeneral = false;

    for (final g in groups) {
      final trimmed = g.name.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.toLowerCase() == defaultGroup.toLowerCase()) {
        hasGeneral = true;
        sanitized.add(ProfileGroup(name: defaultGroup, colorHex: g.colorHex));
      } else {
        sanitized.add(ProfileGroup(name: trimmed, colorHex: g.colorHex));
      }
    }

    if (!hasGeneral) {
      sanitized.add(const ProfileGroup(name: defaultGroup));
    }

    final encoded = sanitized.map((g) => g.encode()).toList();
    await preferences.setStringList(_groupsKey, encoded);
  }

  /// Adds a group named [name], silently, if it does not already exist.
  ///
  /// Blank and duplicate names are no-ops rather than throws: the forms
  /// check first and say so, and a throw from here would surface as an
  /// unhandled error the moment two callers raced for the same name.
  Future<void> addGroup(String name, {String? colorHex}) =>
      _writes.run(() async {
        final trimmed = name.trim();
        if (trimmed.isEmpty) return;

        final groups = await loadGroups();
        if (groups.any((g) => g.name.toLowerCase() == trimmed.toLowerCase())) {
          return;
        }

        groups.add(ProfileGroup(name: trimmed, colorHex: colorHex));
        await saveGroups(groups);
      });

  Future<void> renameGroup(String oldName, String newName) =>
      updateGroup(oldName, name: newName);

  /// Renames or recolours the group named [oldName], silently no-oping
  /// rather than throwing when [name] is blank, the group is [defaultGroup]
  /// (which cannot be renamed away) or the new name collides with a
  /// different existing group.
  ///
  /// When the name actually changes, every profile, key and snippet carrying
  /// [oldName] is reassigned to it.
  Future<void> updateGroup(
    String oldName, {
    String? name,
    String? colorHex,
    bool clearColor = false,
  }) => _writes.run(() async {
    final groups = await loadGroups();
    final index = groups.indexWhere(
      (g) => g.name.toLowerCase() == oldName.trim().toLowerCase(),
    );
    if (index == -1) return;

    final existing = groups[index];
    final trimmedNew = name?.trim();

    if (name != null && trimmedNew!.isEmpty) return;

    if (existing.name.toLowerCase() == defaultGroup.toLowerCase() &&
        trimmedNew != null &&
        trimmedNew.toLowerCase() != defaultGroup.toLowerCase()) {
      return;
    }

    if (trimmedNew != null &&
        trimmedNew.toLowerCase() != existing.name.toLowerCase()) {
      final collision = groups.any(
        (g) =>
            g.name.toLowerCase() == trimmedNew.toLowerCase() &&
            g.name.toLowerCase() != existing.name.toLowerCase(),
      );
      if (collision) return;
    }

    final targetName = trimmedNew ?? existing.name;
    final String? targetColor;
    if (name == null) {
      targetColor = colorHex;
    } else if (clearColor) {
      targetColor = null;
    } else if (colorHex != null) {
      targetColor = colorHex;
    } else {
      targetColor = existing.colorHex;
    }

    final updated = ProfileGroup(name: targetName, colorHex: targetColor);
    groups[index] = updated;
    await saveGroups(groups);

    if (targetName != existing.name) {
      final profiles = await _profiles.loadProfiles();
      var profilesChanged = false;
      for (var i = 0; i < profiles.length; i++) {
        if (isSameGroup(profiles[i].group, existing.name)) {
          profiles[i] = profiles[i].copyWith(group: targetName);
          profilesChanged = true;
        }
      }
      if (profilesChanged) {
        await _profiles.saveProfiles(profiles);
      }

      final keys = await _keys.loadKeys();
      var keysChanged = false;
      for (var i = 0; i < keys.length; i++) {
        if (isSameGroup(keys[i].group, existing.name)) {
          keys[i] = keys[i].copyWith(group: targetName);
          keysChanged = true;
        }
      }
      if (keysChanged) {
        await _keys.saveKeys(keys);
      }

      final snippets = await _snippets.loadSnippets();
      var snippetsChanged = false;
      for (var i = 0; i < snippets.length; i++) {
        if (isSameGroup(snippets[i].group, existing.name)) {
          snippets[i] = snippets[i].copyWith(group: targetName);
          snippetsChanged = true;
        }
      }
      if (snippetsChanged) {
        await _snippets.saveSnippets(snippets);
      }
    }
  });

  Future<void> deleteGroup(String name) => _writes.run(() async {
    final trimmed = name.trim();
    if (trimmed.toLowerCase() == defaultGroup.toLowerCase()) return;

    final groups = await loadGroups();
    final index = groups.indexWhere(
      (g) => g.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (index == -1) return;

    final removedName = groups[index].name;
    groups.removeAt(index);
    await saveGroups(groups);

    final profiles = await _profiles.loadProfiles();
    var profilesChanged = false;
    for (var i = 0; i < profiles.length; i++) {
      if (isSameGroup(profiles[i].group, removedName)) {
        profiles[i] = profiles[i].copyWith(group: defaultGroup);
        profilesChanged = true;
      }
    }
    if (profilesChanged) {
      await _profiles.saveProfiles(profiles);
    }

    final keys = await _keys.loadKeys();
    var keysChanged = false;
    for (var i = 0; i < keys.length; i++) {
      if (isSameGroup(keys[i].group, removedName)) {
        keys[i] = keys[i].copyWith(group: defaultGroup);
        keysChanged = true;
      }
    }
    if (keysChanged) {
      await _keys.saveKeys(keys);
    }

    final snippets = await _snippets.loadSnippets();
    var snippetsChanged = false;
    for (var i = 0; i < snippets.length; i++) {
      if (isSameGroup(snippets[i].group, removedName)) {
        snippets[i] = snippets[i].copyWith(group: defaultGroup);
        snippetsChanged = true;
      }
    }
    if (snippetsChanged) {
      await _snippets.saveSnippets(snippets);
    }
  });
}

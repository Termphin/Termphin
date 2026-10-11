import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profile_group.dart';
import '../../models/snippet.dart';
import '../../models/ssh_profile.dart';
import '../storage/group_storage.dart';
import '../storage/profile_storage.dart';
import '../storage/snippet_storage.dart';
import 'debug_interstitials.dart';

class TagCandidate {
  const TagCandidate({
    required this.name,
    required this.profileCount,
    required this.snippetCount,
  });

  final String name;
  final int profileCount;
  final int snippetCount;

  int get totalCount => profileCount + snippetCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagCandidate &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          profileCount == other.profileCount &&
          snippetCount == other.snippetCount;

  @override
  int get hashCode => Object.hash(name, profileCount, snippetCount);

  @override
  String toString() =>
      'TagCandidate(name: $name, profiles: $profileCount, snippets: $snippetCount)';
}

class TagMigrationPlan {
  const TagMigrationPlan({
    required this.tags,
    required this.recordCount,
    this.isSample = false,
  });

  final List<TagCandidate> tags;
  final int recordCount;

  /// A stand-in shown while testing, not something read off this device. It is
  /// answered like any other plan, but answering it must not rewrite records
  /// or prune groups - there is nothing behind it to rewrite.
  final bool isSample;

  bool get isEmpty => tags.isEmpty || recordCount == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagMigrationPlan &&
          runtimeType == other.runtimeType &&
          recordCount == other.recordCount &&
          listEquals(tags, other.tags);

  @override
  int get hashCode => Object.hash(recordCount, Object.hashAll(tags));

  @override
  String toString() =>
      'TagMigrationPlan(recordCount: $recordCount, tags: $tags)';
}

class TagMigrationService {
  TagMigrationService({
    ProfileStorage? profiles,
    SnippetStorage? snippets,
    GroupStorage? groups,
    SharedPreferences? preferences,
  }) : _profiles = profiles ?? ProfileStorage(),
       _snippets = snippets ?? SnippetStorage(),
       _groups = groups ?? GroupStorage(profiles: profiles, snippets: snippets),
       _preferences = preferences;

  static const String doneKey = 'tag_migration_done_v1';

  final ProfileStorage _profiles;
  final SnippetStorage _snippets;
  final GroupStorage _groups;
  final SharedPreferences? _preferences;

  Future<SharedPreferences> _getPrefs() async =>
      _preferences ?? await SharedPreferences.getInstance();

  /// Scans the legacy `tags` fields still on disk and plans the groups they
  /// would become. A profile or snippet entry that fails to decode is
  /// skipped rather than failing the whole scan.
  Future<TagMigrationPlan> detect() async {
    final prefs = await _getPrefs();

    final profileCounts = <String, int>{};
    final snippetCounts = <String, int>{};
    final tagCasing = <String, String>{};
    final firstSeen = <String, int>{};
    var taggedRecords = 0;

    final rawProfiles = prefs.getStringList('ssh_profiles') ?? <String>[];
    for (final raw in rawProfiles) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json.containsKey('tags') && json['tags'] is List) {
          final tags = (json['tags'] as List)
              .map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet();
          if (tags.isNotEmpty) {
            taggedRecords++;
            for (final tag in tags) {
              final lower = tag.toLowerCase();
              tagCasing.putIfAbsent(lower, () => tag);
              firstSeen.putIfAbsent(lower, () => firstSeen.length);
              profileCounts[lower] = (profileCounts[lower] ?? 0) + 1;
            }
          }
        }
      } catch (_) {}
    }

    final rawSnippets = prefs.getStringList('snippets') ?? <String>[];
    for (final raw in rawSnippets) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json.containsKey('tags') && json['tags'] is List) {
          final tags = (json['tags'] as List)
              .map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet();
          if (tags.isNotEmpty) {
            taggedRecords++;
            for (final tag in tags) {
              final lower = tag.toLowerCase();
              tagCasing.putIfAbsent(lower, () => tag);
              firstSeen.putIfAbsent(lower, () => firstSeen.length);
              snippetCounts[lower] = (snippetCounts[lower] ?? 0) + 1;
            }
          }
        }
      } catch (_) {}
    }

    final candidates = <TagCandidate>[];
    for (final lower in tagCasing.keys) {
      candidates.add(
        TagCandidate(
          name: tagCasing[lower]!,
          profileCount: profileCounts[lower] ?? 0,
          snippetCount: snippetCounts[lower] ?? 0,
        ),
      );
    }

    candidates.sort((a, b) {
      final totalCmp = b.totalCount.compareTo(a.totalCount);
      if (totalCmp != 0) return totalCmp;
      final aSeen = firstSeen[a.name.toLowerCase()] ?? 0;
      final bSeen = firstSeen[b.name.toLowerCase()] ?? 0;
      return aSeen.compareTo(bSeen);
    });

    final plan = TagMigrationPlan(tags: candidates, recordCount: taggedRecords);
    if (plan.isEmpty && _forcing) return sampleTagMigrationPlan();
    return plan;
  }

  /// Set by tests that need the forced path on or off deterministically - a
  /// test runs in debug mode, so it would otherwise inherit whatever
  /// [kForceInterstitials] happens to be set to while somebody is testing.
  @visibleForTesting
  static bool? debugForceOverride;

  /// Only ever true on a debug build, and only while the testing switch is on.
  bool get _forcing =>
      kDebugMode && (debugForceOverride ?? kForceInterstitials);

  /// Turns [keptTags] into groups and reassigns every profile and snippet
  /// to one of them.
  ///
  /// Against [TagMigrationPlan.isSample], only adds what was ticked: the
  /// pruning below sets the group list to exactly the kept tags, which
  /// against a stand-in would delete the tester's real groups and move
  /// every record to [GroupStorage.defaultGroup].
  Future<void> apply(Set<String> keptTags) async {
    final prefs = await _getPrefs();
    final plan = await detect();

    if (plan.isSample) {
      for (final name in keptTags) {
        await _groups.addGroup(name);
      }
      return;
    }

    final keptLower = keptTags.map((t) => t.toLowerCase()).toSet();

    final groupsToSave = <ProfileGroup>[
      const ProfileGroup(name: GroupStorage.defaultGroup),
    ];
    for (final candidate in plan.tags) {
      if (keptLower.contains(candidate.name.toLowerCase()) &&
          candidate.name.toLowerCase() !=
              GroupStorage.defaultGroup.toLowerCase()) {
        groupsToSave.add(ProfileGroup(name: candidate.name));
      }
    }
    await _groups.saveGroups(groupsToSave);

    final rawProfiles = prefs.getStringList('ssh_profiles') ?? <String>[];
    final profileTags = <String, List<String>>{};
    for (final raw in rawProfiles) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final id = json['id'] as String?;
        if (id != null && json.containsKey('tags') && json['tags'] is List) {
          profileTags[id] = (json['tags'] as List)
              .map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    final rawSnippets = prefs.getStringList('snippets') ?? <String>[];
    final snippetTags = <String, List<String>>{};
    for (final raw in rawSnippets) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final id = json['id'] as String?;
        if (id != null && json.containsKey('tags') && json['tags'] is List) {
          snippetTags[id] = (json['tags'] as List)
              .map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    final profiles = await _profiles.loadProfiles();
    final updatedProfiles = <SshProfile>[];
    for (final profile in profiles) {
      final tags = profileTags[profile.id];
      String? assignedGroup;
      if (tags != null && tags.isNotEmpty) {
        for (final tag in tags) {
          TagCandidate? match;
          for (final c in plan.tags) {
            if (keptLower.contains(c.name.toLowerCase()) &&
                c.name.toLowerCase() == tag.toLowerCase()) {
              match = c;
              break;
            }
          }
          if (match != null) {
            assignedGroup = match.name;
            break;
          }
        }
      }
      updatedProfiles.add(
        profile.copyWith(group: assignedGroup ?? GroupStorage.defaultGroup),
      );
    }
    await _profiles.saveProfiles(updatedProfiles);

    final snippets = await _snippets.loadSnippets();
    final updatedSnippets = <Snippet>[];
    for (final snippet in snippets) {
      final tags = snippetTags[snippet.id];
      String? assignedGroup;
      if (tags != null && tags.isNotEmpty) {
        for (final tag in tags) {
          TagCandidate? match;
          for (final c in plan.tags) {
            if (keptLower.contains(c.name.toLowerCase()) &&
                c.name.toLowerCase() == tag.toLowerCase()) {
              match = c;
              break;
            }
          }
          if (match != null) {
            assignedGroup = match.name;
            break;
          }
        }
      }
      updatedSnippets.add(
        snippet.copyWith(group: assignedGroup ?? GroupStorage.defaultGroup),
      );
    }
    await _snippets.saveSnippets(updatedSnippets);

    await prefs.setBool(GroupStorage.migratedKey, true);
    if (!_forcing) await prefs.setBool(doneKey, true);
  }

  Future<void> skip() async {
    final prefs = await _getPrefs();

    if ((await detect()).isSample) return;

    await _groups.saveGroups([
      const ProfileGroup(name: GroupStorage.defaultGroup),
    ]);

    final profiles = await _profiles.loadProfiles();
    final updatedProfiles = profiles
        .map((p) => p.copyWith(group: GroupStorage.defaultGroup))
        .toList();
    await _profiles.saveProfiles(updatedProfiles);

    final snippets = await _snippets.loadSnippets();
    final updatedSnippets = snippets
        .map((s) => s.copyWith(group: GroupStorage.defaultGroup))
        .toList();
    await _snippets.saveSnippets(updatedSnippets);

    await prefs.setBool(GroupStorage.migratedKey, true);
    if (!_forcing) await prefs.setBool(doneKey, true);
  }

  Future<bool> isPending() async {
    final prefs = await _getPrefs();
    final done = prefs.getBool(doneKey) ?? false;
    if (done && !_forcing) return false;
    final plan = await detect();
    return !plan.isEmpty;
  }
}

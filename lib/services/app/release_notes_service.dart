import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import 'version_compare.dart';

const kLastSeenReleaseNotesVersionPrefsKey = 'last_seen_release_notes_version';

const _releaseNotesAssetPath = 'assets/release_notes.yaml';

/// Keep a Changelog (https://keepachangelog.com) category order.
const _releaseNoteCategoryKeys = [
  'added',
  'changed',
  'deprecated',
  'removed',
  'fixed',
  'security',
];

class ReleaseNoteCategory {
  const ReleaseNoteCategory({required this.label, required this.items});

  final String label;
  final List<String> items;
}

class ReleaseNoteEntry {
  const ReleaseNoteEntry({
    required this.version,
    required this.date,
    required this.categories,
  });

  final String version;
  final String date;
  final List<ReleaseNoteCategory> categories;
}

/// Drives the "what's new" sheet shown after an update.
///
/// `assets/release_notes.yaml` is the single source of truth: this service
/// reads it in-app, and the website's build pulls the same file in to
/// render its changelog page.
class ReleaseNotesService {
  ReleaseNotesService._();
  static final ReleaseNotesService instance = ReleaseNotesService._();

  List<ReleaseNoteEntry>? _cache;

  /// Parses and caches `assets/release_notes.yaml`.
  ///
  /// An `Unreleased` entry is work that has landed with no version decided
  /// for it yet. Dropping it here is what keeps it out of the changelog
  /// screen and the post-update sheet at once, and keeps a version string
  /// [compareVersions] cannot parse away from every caller below.
  Future<List<ReleaseNoteEntry>> _loadEntries() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(_releaseNotesAssetPath);
    final doc = loadYaml(raw) as YamlList;
    final entries = doc
        .where((e) => isReleasedVersion(e['version'] as String))
        .map((e) {
          final categories = <ReleaseNoteCategory>[
            for (final key in _releaseNoteCategoryKeys)
              if (e[key] != null && (e[key] as YamlList).isNotEmpty)
                ReleaseNoteCategory(
                  label: '${key[0].toUpperCase()}${key.substring(1)}',
                  items: (e[key] as YamlList).cast<String>(),
                ),
          ];
          return ReleaseNoteEntry(
            version: e['version'] as String,
            date: e['date'] as String,
            categories: categories,
          );
        })
        .toList();
    _cache = entries;
    return entries;
  }

  /// Entries newer than the last version this device has seen, up to and
  /// including [currentVersion], newest first. On the very first check after
  /// this feature ships - or on a fresh install - there is no "last seen"
  /// yet, so this records [currentVersion] as seen without returning
  /// anything: nobody gets the full historical changelog dumped on them.
  Future<List<ReleaseNoteEntry>> pendingSince(String currentVersion) async {
    final preferences = await SharedPreferences.getInstance();
    final lastSeen = preferences.getString(
      kLastSeenReleaseNotesVersionPrefsKey,
    );
    if (lastSeen == null) {
      await preferences.setString(
        kLastSeenReleaseNotesVersionPrefsKey,
        currentVersion,
      );
      return const [];
    }
    final entries = await _loadEntries();
    final pending = entries.where((entry) {
      return compareVersions(entry.version, lastSeen) > 0 &&
          compareVersions(entry.version, currentVersion) <= 0;
    }).toList();
    pending.sort((a, b) => compareVersions(b.version, a.version));
    return pending;
  }

  /// Full history, newest first - for the Settings screen's review link.
  Future<List<ReleaseNoteEntry>> allEntries() async {
    final entries = await _loadEntries();
    final sorted = [...entries];
    sorted.sort((a, b) => compareVersions(b.version, a.version));
    return sorted;
  }

  Future<void> markSeen(String version) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(kLastSeenReleaseNotesVersionPrefsKey, version);
  }
}

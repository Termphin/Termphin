import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import 'debug_interstitials.dart';
import 'version_compare.dart';

const kSeenWhatsNewIdsPrefsKey = 'seen_whats_new_ids';

const _whatsNewAssetPath = 'assets/whats_new.yaml';

/// One page of the what's-new popup: a feature, named and described.
class ReleaseHighlight {
  const ReleaseHighlight({
    required this.id,
    required this.version,
    required this.title,
    required this.body,
    this.image,
    this.imageAspect,
    this.setting,
    this.announce = true,
  });

  /// Stable, unique, and never reused. This - not the version - is what
  /// decides whether a device has already been shown this page, so renaming
  /// or re-dating a release cannot resurrect it, and a highlight added to an
  /// older release's block later still gets its turn.
  final String id;

  /// The release that introduced it. Only a ceiling: a highlight written
  /// ahead of the release it belongs to stays hidden until the build catches
  /// up with it.
  final String version;

  final String title;
  final String body;

  /// Asset path, or null for a text-only page. An animated GIF plays.
  final String? image;

  /// Width over height of [image], for one that is not the default banner
  /// shape - a screen recording, say.
  final double? imageAspect;

  /// Preferences key of a setting the page offers a switch for, so a feature
  /// can be turned off where it is announced.
  final String? setting;

  /// False for a page that only explains a feature from beside its setting:
  /// one that has been around too long to be announced as new.
  final bool announce;
}

/// `"9:16"` as 0.5625; null for anything else.
double? parseAspect(Object? raw) {
  if (raw is! String) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final w = double.tryParse(parts[0].trim());
  final h = double.tryParse(parts[1].trim());
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return w / h;
}

/// Drives the popup shown once after an update.
///
/// Reads `assets/whats_new.yaml`, which is hand-written per release and only
/// covers new features. The changelog is a separate artefact with a separate
/// life - see [ReleaseNotesService] - because generating this from it is
/// what produced a wall of bullet points nobody read.
class WhatsNewService {
  WhatsNewService._({bool? forcing}) : _debugForcing = forcing;
  static final WhatsNewService instance = WhatsNewService._();

  /// Creates a test instance with an optional forcing override.
  @visibleForTesting
  WhatsNewService.forTesting({bool? forcing}) : _debugForcing = forcing;

  bool? _debugForcing;

  /// Overrides whether the what's-new popup is forced open. Tests only.
  @visibleForTesting
  void debugSetForcing(bool? forcing) {
    _debugForcing = forcing;
  }

  /// Whether the what's-new popup is forced open for testing.
  ///
  /// Every read goes through [kDebugMode] so a release build ignores it
  /// whatever the testing switch says.
  bool get _forcing => kDebugMode && (_debugForcing ?? kForceInterstitials);

  List<ReleaseHighlight>? _cache;

  /// Overrides the bundled asset. Tests only.
  void debugSetHighlights(List<ReleaseHighlight>? highlights) {
    _cache = highlights;
  }

  Future<List<ReleaseHighlight>> _loadHighlights() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(_whatsNewAssetPath);
    final doc = loadYaml(raw) as YamlList;
    final highlights = <ReleaseHighlight>[
      for (final entry in doc)
        for (final highlight in (entry['highlights'] as YamlList? ?? []))
          ReleaseHighlight(
            id: highlight['id'] as String,
            version: entry['version'] as String,
            title: highlight['title'] as String,
            body: highlight['body'] as String,
            image: highlight['image'] as String?,
            imageAspect: parseAspect(highlight['aspect']),
            setting: highlight['setting'] as String?,
            announce: highlight['announce'] as bool? ?? true,
          ),
    ];
    _cache = highlights;
    return highlights;
  }

  /// Safely compares two version strings without throwing on non-numeric
  /// (unreleased) versions. Released versions sort normally; unreleased
  /// versions sort last.
  int _compareVersionsSafe(String a, String b) {
    final aReleased = isReleasedVersion(a);
    final bReleased = isReleasedVersion(b);
    if (aReleased && bReleased) {
      return compareVersions(a, b);
    }
    if (aReleased && !bReleased) {
      return -1;
    }
    if (!aReleased && bReleased) {
      return 1;
    }
    return a.compareTo(b);
  }

  /// Collapses repeats of an id down to one page - the newest of them.
  ///
  /// An id is one announcement, not one yaml row. Repeating it under a later
  /// version says "this is still the same thing, reworded" - so someone who
  /// already saw it never sees it again, and someone meeting it for the
  /// first time gets one page carrying the most recent wording rather than
  /// the same feature twice in a row.
  List<ReleaseHighlight> _collapseById(List<ReleaseHighlight> highlights) {
    final newest = <String, ReleaseHighlight>{};
    for (final highlight in highlights) {
      final existing = newest[highlight.id];
      if (existing == null ||
          _compareVersionsSafe(highlight.version, existing.version) > 0) {
        newest[highlight.id] = highlight;
      }
    }
    return newest.values.toList();
  }

  /// The highlight [id], in its newest wording, whatever its version - for a
  /// setting that explains itself with the page that announced it. Reading
  /// it records nothing as seen.
  Future<ReleaseHighlight?> highlight(String id) async {
    final matching = (await _loadHighlights()).where((h) => h.id == id);
    return _collapseById(matching.toList()).firstOrNull;
  }

  /// Highlights this device has not been shown yet, oldest release first so
  /// paging forward moves forward in time.
  ///
  /// Anything written against a version above [currentVersion] is held back
  /// until the build reaches it.
  ///
  /// The first run ever - a fresh install, or an upgrade from a build that
  /// predates this file - seeds every highlight it can currently see as
  /// already shown and returns nothing. Someone who has just installed the
  /// app is not catching up on anything, and onboarding already has their
  /// attention; someone upgrading into this feature should not be handed the
  /// entire backlog at once either. From then on, only genuinely new ids
  /// appear, which is exactly what an update should surface. Only what has
  /// actually been released is seeded - seeding everything would bury a
  /// highlight written ahead of its version before it ever shows.
  ///
  /// When forcing is active (in debug builds with [kForceInterstitials]), all
  /// highlights are returned on every launch, ignoring what has already been
  /// seen, skipping first-run seeding, and ignoring the version ceiling and
  /// unreleased filter.
  Future<List<ReleaseHighlight>> pendingSince(String currentVersion) async {
    final highlights = [
      for (final highlight in await _loadHighlights())
        if (highlight.announce) highlight,
    ];
    if (_forcing) {
      final forced = _collapseById(highlights);
      forced.sort((a, b) => _compareVersionsSafe(a.version, b.version));
      return forced;
    }

    final preferences = await SharedPreferences.getInstance();
    final released = _collapseById(
      highlights
          .where(
            (h) =>
                isReleasedVersion(h.version) &&
                compareVersions(h.version, currentVersion) <= 0,
          )
          .toList(),
    );

    final seen = preferences.getStringList(kSeenWhatsNewIdsPrefsKey);
    if (seen == null) {
      await preferences.setStringList(
        kSeenWhatsNewIdsPrefsKey,
        released.map((h) => h.id).toList(),
      );
      return const [];
    }

    final seenIds = seen.toSet();
    final pending = released.where((h) => !seenIds.contains(h.id)).toList();
    pending.sort((a, b) => compareVersions(a.version, b.version));
    return pending;
  }

  /// Records [highlights] as shown, so they never come back.
  ///
  /// Does nothing when [_forcing] is active, allowing subsequent launches
  /// to show highlights again.
  Future<void> markSeen(Iterable<ReleaseHighlight> highlights) async {
    if (_forcing) return;
    final preferences = await SharedPreferences.getInstance();
    final seen = {
      ...?preferences.getStringList(kSeenWhatsNewIdsPrefsKey),
      ...highlights.map((h) => h.id),
    };
    await preferences.setStringList(kSeenWhatsNewIdsPrefsKey, seen.toList());
  }
}

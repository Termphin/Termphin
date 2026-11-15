import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

const kLegalUpdateSeenPrefsKey = 'legal_update_seen';

const _legalUpdatesAssetPath = 'assets/legal_updates.yaml';

/// A change to the terms of service or the privacy policy, from
/// `assets/legal_updates.yaml`.
@immutable
class LegalUpdate {
  const LegalUpdate({
    required this.id,
    required this.material,
    required this.summary,
  });

  /// The change's date, `YYYY-MM-DD`: ids sort as the changes happened.
  final String id;
  final bool material;
  final String summary;
}

/// Tells someone who already uses the app that the terms or the privacy
/// policy changed in a way that matters, once.
///
/// Nobody is asked to accept anything again: the privacy policy is
/// information, and the terms go on by using the app, so a notice with the
/// links is what is owed. Someone new reads both at the end of onboarding,
/// which marks every change so far as seen, so they are never told about a
/// change that happened before they arrived.
class LegalUpdatesService {
  LegalUpdatesService._();

  static final instance = LegalUpdatesService._();

  /// Stands in for the bundled file in tests.
  @visibleForTesting
  String? sourceOverride;

  Future<List<LegalUpdate>> _load() async {
    final raw =
        sourceOverride ?? await rootBundle.loadString(_legalUpdatesAssetPath);
    final doc = loadYaml(raw);
    if (doc is! YamlList) return const [];
    return [
      for (final entry in doc)
        if (entry is YamlMap && entry['id'] != null)
          LegalUpdate(
            id: '${entry['id']}',
            material: entry['material'] == true,
            summary: '${entry['summary'] ?? ''}'.trim(),
          ),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// The newest material change this device has not been told about, or
  /// null when there is none.
  Future<LegalUpdate?> pending() async {
    final preferences = await SharedPreferences.getInstance();
    final seen = preferences.getString(kLegalUpdateSeenPrefsKey) ?? '';
    final unseen = (await _load()).where(
      (update) => update.material && update.id.compareTo(seen) > 0,
    );
    return unseen.lastOrNull;
  }

  /// The newest material change, seen or not. For the debug panel.
  Future<LegalUpdate?> latest() async =>
      (await _load()).where((update) => update.material).lastOrNull;

  /// Marks every change made up to today as seen. Ids are dates, so the
  /// date itself is what is stored - no need to read the file for it.
  Future<void> markSeen() async {
    final now = clock.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(kLegalUpdateSeenPrefsKey, today);
  }
}

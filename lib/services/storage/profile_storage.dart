import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ssh_profile.dart';
import '../security/secret_cipher.dart';
import 'write_queue.dart';

/// Fields sealed before they reach SharedPreferences. Everything else about a
/// profile stays readable - only credentials are worth the round trip.
const _secretFields = ['password', 'privateKey', 'passphrase'];

class ProfileStorage {
  ProfileStorage({SecretCipher? cipher})
    : _cipher = cipher ?? SecretCipher.instance;

  static const String _profilesKey = 'ssh_profiles';

  /// Shared by every instance: two `ProfileStorage()` objects are two views of
  /// one SharedPreferences key, so a queue per instance would serialise
  /// nothing. Each mutation below is a load-modify-save, and two of those
  /// overlapping means the second reads the state from before the first one's
  /// write and then erases it.
  static final WriteQueue _writes = WriteQueue();

  final SecretCipher _cipher;

  /// Profiles, newest first. Records written before encryption shipped are
  /// rewritten sealed the first time they are read, so the migration needs
  /// no separate step.
  Future<List<SshProfile>> loadProfiles() async {
    final (profiles, sawPlaintext) = await _read();
    if (sawPlaintext) await saveProfiles(profiles);
    return profiles;
  }

  /// Decodes what is on disk. Kept separate from [loadProfiles] so
  /// [saveProfiles] can look at the stored records without re-entering the
  /// migration that calls it. An entry that fails to decode is skipped
  /// instead, so the rest of the profiles are still available.
  Future<(List<SshProfile>, bool)> _read() async {
    final preferences = await SharedPreferences.getInstance();
    final rawProfiles = preferences.getStringList(_profilesKey) ?? <String>[];
    final profiles = <SshProfile>[];
    var sawPlaintext = false;
    for (final rawProfile in rawProfiles) {
      try {
        final json = jsonDecode(rawProfile) as Map<String, dynamic>;
        final id = json['id'] as String;
        for (final field in _secretFields) {
          final value = json[field] as String?;
          if (value == null) continue;
          if (!_cipher.isSealed(value)) sawPlaintext = true;
          json[field] = await _cipher.open(value, aad: '$id/$field');
        }
        profiles.add(SshProfile.fromJson(json));
      } catch (_) {}
    }
    profiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return (profiles, sawPlaintext);
  }

  Future<void> saveProfiles(List<SshProfile> profiles) async {
    final preferences = await SharedPreferences.getInstance();
    final sorted = [...profiles]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final encoded = <String>[];
    for (final profile in sorted) {
      final json = profile.toJson();
      for (final field in _secretFields) {
        final value = json[field] as String?;
        if (value == null || value.isEmpty) continue;
        json[field] = await _cipher.seal(value, aad: '${profile.id}/$field');
      }
      encoded.add(jsonEncode(json));
    }
    await preferences.setStringList(_profilesKey, encoded);
  }

  Future<SshProfile?> getProfile(String profileId) async {
    final profiles = await loadProfiles();
    for (final profile in profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  Future<void> addProfile(SshProfile profile) => _writes.run(() async {
    final profiles = await loadProfiles();
    profiles.add(profile);
    await saveProfiles(profiles);
  });

  Future<void> updateProfile(SshProfile profile) => _writes.run(() async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      throw StateError('Profile not found.');
    }
    profiles[index] = profile;
    await saveProfiles(profiles);
  });

  Future<void> deleteProfile(String profileId) => _writes.run(() async {
    final profiles = await loadProfiles();
    profiles.removeWhere((profile) => profile.id == profileId);
    await saveProfiles(profiles);
  });
}

import 'dart:convert';

import '../../models/known_host.dart';
import '../../models/profile_group.dart';
import '../../models/snippet.dart';
import '../../models/ssh_key.dart';
import '../../models/ssh_profile.dart';
import '../settings/setting.dart';
import '../storage/group_storage.dart';
import '../storage/known_hosts_store.dart';
import '../storage/profile_storage.dart';
import '../storage/snippet_storage.dart';
import '../storage/ssh_key_storage.dart';
import 'app_preferences_backup.dart';
import 'backup_crypto.dart';
import 'backup_models.dart';

export 'backup_models.dart';

const kLastBackupAtPrefsKey = 'last_backup_at';

/// When a backup was last written from this device, ISO-8601, empty for
/// never. A record of something that happened rather than a preference, so
/// nothing reports it to analytics.
final Setting<String> lastBackupAtSetting = Setting<String>(
  key: kLastBackupAtPrefsKey,
  fallback: '',
  track: false,
  read: (preferences) => preferences.getString(kLastBackupAtPrefsKey) ?? '',
  write: (preferences, value) =>
      preferences.setString(kLastBackupAtPrefsKey, value),
);

class ExportService {
  ExportService({
    ProfileStorage? profileStorage,
    SshKeyStorage? keyStorage,
    SnippetStorage? snippetStorage,
    KnownHostsStore? knownHosts,
    GroupStorage? groupStorage,
  }) : _profileStorage = profileStorage ?? ProfileStorage(),
       _keyStorage = keyStorage ?? SshKeyStorage(),
       _snippetStorage = snippetStorage ?? SnippetStorage(),
       _knownHosts = knownHosts ?? KnownHostsStore.instance,
       _groupStorage =
           groupStorage ??
           GroupStorage(
             profiles: profileStorage,
             keys: keyStorage,
             snippets: snippetStorage,
           );

  final ProfileStorage _profileStorage;
  final SshKeyStorage _keyStorage;
  final SnippetStorage _snippetStorage;
  final KnownHostsStore _knownHosts;
  final GroupStorage _groupStorage;

  /// What this device holds, for a screen that wants to say what an export
  /// will contain before it writes one.
  Future<BackupContents> contents() async => BackupContents(
    profiles: (await _profileStorage.loadProfiles()).length,
    sshKeys: (await _keyStorage.loadKeys()).length,
    snippets: (await _snippetStorage.loadSnippets()).length,
    knownHosts: (await _knownHosts.entries()).length,
  );

  /// The backup as JSON, sealed with [passphrase] when one is given.
  ///
  /// A profile's key passphrase is as much a credential as the key it opens,
  /// so it travels with the secrets rather than unconditionally.
  Future<String> exportToJson(
    ExportOptions options, {
    String? passphrase,
  }) async {
    final data = <String, dynamic>{
      'format': kBackupFormat,
      'version': kBackupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
    };

    final groups = await _groupStorage.loadGroups();
    data['groups'] = groups.map((g) => g.toJson()).toList();

    if (options.includeProfiles) {
      final profiles = await _profileStorage.loadProfiles();
      data['profiles'] = profiles.map((p) {
        final json = Map<String, dynamic>.from(p.toJson());
        if (!options.includePasswords) json.remove('password');
        if (!options.includeInlinePrivateKeys) json.remove('privateKey');
        if (!options.includePasswords && !options.includeInlinePrivateKeys) {
          json.remove('passphrase');
        }
        return json;
      }).toList();
    }

    if (options.includeSshKeys) {
      final keys = await _keyStorage.loadKeys();
      data['sshKeys'] = keys.map((k) => k.toJson()).toList();
    }

    if (options.includeSnippets) {
      final snippets = await _snippetStorage.loadSnippets();
      data['snippets'] = snippets.map((s) => s.toJson()).toList();
    }

    if (options.includeKnownHosts) {
      final hosts = await _knownHosts.entries();
      data['knownHosts'] = hosts.map((h) => h.toJson()).toList();
    }

    if (options.includeTerminalSettings) {
      data['terminalSettings'] = await exportTerminalSettings();
    }

    if (options.includeAppPreferences) {
      data['appPreferences'] = await exportAppPreferences();
    }

    final json = const JsonEncoder.withIndent('  ').convert(data);
    if (passphrase == null || passphrase.isEmpty) return json;
    return encryptBackup(json, passphrase);
  }

  /// Reads [raw] as a backup and lists what is in it against what this device
  /// already has.
  ///
  /// Throws [BackupFormatException]: [BackupProblem.notABackup] for a file
  /// carrying neither our marker nor a single known section,
  /// [BackupProblem.unsupportedVersion] for one written by a newer build, and
  /// [BackupProblem.passphraseRequired] for a sealed file reached without one.
  ///
  /// Files written before the format marker existed are still ours; they are
  /// recognised by a version plus at least one section we know how to read.
  Future<ImportPreview> inspect(String raw, {String? passphrase}) async {
    var payloadRaw = raw;
    var wasEncrypted = false;
    if (isEncryptedBackup(raw)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const BackupFormatException(BackupProblem.passphraseRequired);
      }
      payloadRaw = await decryptBackup(raw, passphrase);
      wasEncrypted = true;
    }

    final Map<String, dynamic> data;
    final decoded = _tryDecode(payloadRaw);
    if (decoded == null) {
      throw const BackupFormatException(BackupProblem.notABackup);
    }
    data = decoded;

    final version = (data['version'] as num?)?.toInt();
    final looksLikeOurs =
        data['format'] == kBackupFormat ||
        (version != null && _knownSections.any(data.containsKey));
    if (!looksLikeOurs) {
      throw const BackupFormatException(BackupProblem.notABackup);
    }
    if (version == null ||
        version < kMinBackupVersion ||
        version > kBackupVersion) {
      throw const BackupFormatException(BackupProblem.unsupportedVersion);
    }

    final rawDate = data['exportedAt'] as String?;
    final exportedAt = rawDate != null
        ? (DateTime.tryParse(rawDate) ?? DateTime.now())
        : DateTime.now();

    final existingProfiles = {
      for (final profile in await _profileStorage.loadProfiles()) profile.id,
    };
    final existingKeys = {
      for (final key in await _keyStorage.loadKeys()) key.id,
    };
    final existingSnippets = {
      for (final snippet in await _snippetStorage.loadSnippets()) snippet.id,
    };
    final existingHosts = {
      for (final host in await _knownHosts.entries()) host.slot,
    };
    final existingGroupNames = {
      for (final group in await _groupStorage.loadGroups())
        group.name.toLowerCase(),
    };

    return ImportPreview(
      version: version,
      exportedAt: exportedAt,
      wasEncrypted: wasEncrypted,
      payload: data,
      profiles: [
        for (final profile in _decodeProfiles(data))
          BackupItem(
            id: profile.id,
            label: profile.name,
            detail: '${profile.username}@${profile.host}',
            exists: existingProfiles.contains(profile.id),
          ),
      ],
      sshKeys: [
        for (final key in _decodeKeys(data))
          BackupItem(
            id: key.id,
            label: key.name,
            detail: key.keyType.name,
            exists: existingKeys.contains(key.id),
          ),
      ],
      snippets: [
        for (final snippet in _decodeSnippets(data))
          BackupItem(
            id: snippet.id,
            label: snippet.name,
            detail: snippet.command,
            exists: existingSnippets.contains(snippet.id),
          ),
      ],
      knownHosts: [
        for (final host in _decodeKnownHosts(data))
          BackupItem(
            id: host.slot,
            label: '${host.host}:${host.port}',
            detail: host.keyType,
            exists: existingHosts.contains(host.slot),
          ),
      ],
      groups: [
        for (final group in _decodeGroups(data))
          BackupItem(
            id: group.name,
            label: group.name,
            detail: group.colorHex,
            exists: existingGroupNames.contains(group.name.toLowerCase()),
          ),
      ],
      hasTerminalSettings: data['terminalSettings'] is Map,
      hasAppPreferences: data['appPreferences'] is Map,
    );
  }

  /// Inspects [raw] and imports it in one go, for callers holding only the
  /// file's text.
  Future<ImportResult> importFromJson(
    String raw,
    ImportOptions options, {
    String? passphrase,
  }) async => importBackup(await inspect(raw, passphrase: passphrase), options);

  /// Writes [preview]'s payload onto this device per [options].
  ///
  /// Groups merge by name: the file's order wins, and groups only this
  /// device has follow it, but an existing group keeps its own name and
  /// colour rather than taking the incoming one's.
  Future<ImportResult> importBackup(
    ImportPreview preview,
    ImportOptions options,
  ) async {
    final data = preview.payload;
    final replace = options.conflicts == ImportConflicts.replace;

    final existingGroups = await _groupStorage.loadGroups();
    var groupList = List<ProfileGroup>.from(existingGroups);
    var addedGroups = 0;
    var skippedGroups = 0;

    if (data.containsKey('groups')) {
      final ordered = <ProfileGroup>[];
      for (final group in _decodeGroups(data)) {
        final trimmed = group.name.trim();
        if (trimmed.isEmpty) continue;
        final lower = trimmed.toLowerCase();
        if (ordered.any((g) => g.name.toLowerCase() == lower)) continue;
        final existing = existingGroups
            .where((g) => g.name.toLowerCase() == lower)
            .firstOrNull;
        if (existing != null) {
          ordered.add(existing);
          skippedGroups++;
        } else {
          ordered.add(ProfileGroup(name: trimmed, colorHex: group.colorHex));
          addedGroups++;
        }
      }
      groupList = [
        ...ordered,
        for (final group in existingGroups)
          if (!ordered.any(
            (g) => g.name.toLowerCase() == group.name.toLowerCase(),
          ))
            group,
      ];
      await _groupStorage.saveGroups(groupList);
    }

    var profileCount = const ImportCount();
    final importedProfiles = <SshProfile>[];
    if (options.mergeProfiles && data.containsKey('profiles')) {
      final byId = {
        for (final profile in await _profileStorage.loadProfiles())
          profile.id: profile,
      };
      var added = 0;
      var replaced = 0;
      var skipped = 0;
      for (final profile in _decodeProfiles(data)) {
        if (!_wanted(options.profileIds, profile.id)) {
          skipped++;
          continue;
        }
        final clash = byId.containsKey(profile.id);
        if (clash && !replace) {
          skipped++;
          continue;
        }
        byId[profile.id] = profile;
        importedProfiles.add(profile);
        clash ? replaced++ : added++;
      }
      if (added + replaced > 0) {
        await _profileStorage.saveProfiles(byId.values.toList());
      }
      profileCount = ImportCount(
        added: added,
        replaced: replaced,
        skipped: skipped,
      );
    }

    var keyCount = const ImportCount();
    final importedKeys = <SshKey>[];
    if (options.mergeSshKeys && data.containsKey('sshKeys')) {
      final byId = {
        for (final key in await _keyStorage.loadKeys()) key.id: key,
      };
      var added = 0;
      var replaced = 0;
      var skipped = 0;
      for (final key in _decodeKeys(data)) {
        if (!_wanted(options.sshKeyIds, key.id)) {
          skipped++;
          continue;
        }
        final clash = byId.containsKey(key.id);
        if (clash && !replace) {
          skipped++;
          continue;
        }
        byId[key.id] = key;
        importedKeys.add(key);
        clash ? replaced++ : added++;
      }
      if (added + replaced > 0) {
        await _keyStorage.saveKeys(byId.values.toList());
      }
      keyCount = ImportCount(
        added: added,
        replaced: replaced,
        skipped: skipped,
      );
    }

    var snippetCount = const ImportCount();
    final importedSnippets = <Snippet>[];
    if (options.importSnippets && data.containsKey('snippets')) {
      final byId = {
        for (final snippet in await _snippetStorage.loadSnippets())
          snippet.id: snippet,
      };
      var added = 0;
      var replaced = 0;
      var skipped = 0;
      for (final snippet in _decodeSnippets(data)) {
        if (!_wanted(options.snippetIds, snippet.id)) {
          skipped++;
          continue;
        }
        final clash = byId.containsKey(snippet.id);
        if (clash && !replace) {
          skipped++;
          continue;
        }
        byId[snippet.id] = snippet;
        importedSnippets.add(snippet);
        clash ? replaced++ : added++;
      }
      if (added + replaced > 0) {
        await _snippetStorage.saveSnippets(byId.values.toList());
      }
      snippetCount = ImportCount(
        added: added,
        replaced: replaced,
        skipped: skipped,
      );
    }

    var hostCount = const ImportCount();
    if (options.importKnownHosts && data.containsKey('knownHosts')) {
      final existing = {
        for (final host in await _knownHosts.entries()) host.slot,
      };
      var added = 0;
      var replaced = 0;
      var skipped = 0;
      for (final host in _decodeKnownHosts(data)) {
        if (!_wanted(options.knownHostSlots, host.slot)) {
          skipped++;
          continue;
        }
        final clash = existing.contains(host.slot);
        if (clash && !replace) {
          skipped++;
          continue;
        }
        await _knownHosts.trust(host);
        clash ? replaced++ : added++;
      }
      hostCount = ImportCount(
        added: added,
        replaced: replaced,
        skipped: skipped,
      );
    }

    var terminalImported = false;
    if (options.importTerminalSettings && data['terminalSettings'] is Map) {
      await importTerminalSettings(
        Map<String, dynamic>.from(data['terminalSettings'] as Map),
      );
      terminalImported = true;
    }

    var preferencesImported = false;
    if (options.importAppPreferences && data['appPreferences'] is Map) {
      await importAppPreferences(
        Map<String, dynamic>.from(data['appPreferences'] as Map),
      );
      preferencesImported = true;
    }

    final referencedGroups = <String>[
      for (final p in importedProfiles) p.group,
      for (final k in importedKeys) k.group,
      for (final s in importedSnippets) s.group,
    ];

    var recordGroupsAdded = 0;
    for (final groupName in referencedGroups) {
      final trimmed = groupName.trim();
      if (trimmed.isEmpty) continue;
      final exists = groupList.any(
        (g) => g.name.toLowerCase() == trimmed.toLowerCase(),
      );
      if (!exists) {
        groupList.add(ProfileGroup(name: trimmed, colorHex: null));
        addedGroups++;
        recordGroupsAdded++;
      }
    }
    if (recordGroupsAdded > 0) {
      await _groupStorage.saveGroups(groupList);
    }

    final groupCount = ImportCount(
      added: addedGroups,
      replaced: 0,
      skipped: skippedGroups,
    );

    final (missingKey, missingJumpHost) = await _danglingReferences(
      importedProfiles,
    );

    return ImportResult(
      profiles: profileCount,
      sshKeys: keyCount,
      snippets: snippetCount,
      knownHosts: hostCount,
      groups: groupCount,
      terminalSettings: terminalImported,
      appPreferences: preferencesImported,
      profilesMissingKey: missingKey,
      profilesMissingJumpHost: missingJumpHost,
    );
  }

  /// Profiles that landed pointing at something that did not - a key left out
  /// of the selection, or a bastion profile skipped as a duplicate.
  Future<(List<String>, List<String>)> _danglingReferences(
    List<SshProfile> imported,
  ) async {
    if (imported.isEmpty) return (const <String>[], const <String>[]);
    final keyIds = {for (final key in await _keyStorage.loadKeys()) key.id};
    final profileIds = {
      for (final profile in await _profileStorage.loadProfiles()) profile.id,
    };
    final missingKey = <String>[];
    final missingJumpHost = <String>[];
    for (final profile in imported) {
      final keyId = profile.sshKeyId;
      if (keyId != null && keyId.isNotEmpty && !keyIds.contains(keyId)) {
        missingKey.add(profile.name);
      }
      final jumpId = profile.jumpHostProfileId;
      if (jumpId != null && jumpId.isNotEmpty && !profileIds.contains(jumpId)) {
        missingJumpHost.add(profile.name);
      }
    }
    return (missingKey, missingJumpHost);
  }

  static const _knownSections = [
    'profiles',
    'sshKeys',
    'snippets',
    'knownHosts',
    'groups',
    'terminalSettings',
    'appPreferences',
  ];

  Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<SshProfile> _decodeProfiles(Map<String, dynamic> data) =>
      _decodeList(data['profiles'], SshProfile.fromJson);

  List<SshKey> _decodeKeys(Map<String, dynamic> data) =>
      _decodeList(data['sshKeys'], SshKey.fromJson);

  List<Snippet> _decodeSnippets(Map<String, dynamic> data) =>
      _decodeList(data['snippets'], Snippet.fromJson);

  List<KnownHost> _decodeKnownHosts(Map<String, dynamic> data) =>
      _decodeList(data['knownHosts'], KnownHost.fromJson);

  List<ProfileGroup> _decodeGroups(Map<String, dynamic> data) =>
      _decodeList(data['groups'], ProfileGroup.fromJson);

  /// Drops the records it cannot read rather than failing the whole file -
  /// one corrupted entry should not cost the other forty.
  List<T> _decodeList<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) decode,
  ) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(decode(Map<String, dynamic>.from(entry)));
      } catch (_) {}
    }
    return out;
  }
}

bool _wanted(Set<String>? selection, String id) =>
    selection == null || selection.contains(id);

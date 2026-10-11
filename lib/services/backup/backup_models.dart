class ExportOptions {
  const ExportOptions({
    this.includeProfiles = true,
    this.includePasswords = false,
    this.includeInlinePrivateKeys = false,
    this.includeSshKeys = true,
    this.includeSnippets = true,
    this.includeKnownHosts = false,
    this.includeTerminalSettings = true,
    this.includeAppPreferences = true,
  });

  final bool includeProfiles;
  final bool includePasswords;
  final bool includeInlinePrivateKeys;
  final bool includeSshKeys;
  final bool includeSnippets;
  final bool includeKnownHosts;
  final bool includeTerminalSettings;
  final bool includeAppPreferences;

  /// Nothing to write. A backup of neither profiles nor settings is a file
  /// holding a timestamp, which is not worth reporting as a success.
  bool get isEmpty =>
      !includeProfiles &&
      !includeSshKeys &&
      !includeSnippets &&
      !includeKnownHosts &&
      !includeTerminalSettings &&
      !includeAppPreferences;

  /// Whether the file will hold credentials. A key in the key manager is a
  /// private key by definition, so that section counts on its own.
  bool get containsSecrets =>
      includeSshKeys ||
      (includeProfiles && (includePasswords || includeInlinePrivateKeys));
}

/// What an id already present on this device does.
enum ImportConflicts {
  /// Keep what is here and count the incoming record as skipped.
  skip,

  /// Overwrite the local record with the incoming one.
  replace,
}

class ImportOptions {
  const ImportOptions({
    this.mergeProfiles = true,
    this.mergeSshKeys = true,
    this.importSnippets = true,
    this.importKnownHosts = true,
    this.importTerminalSettings = true,
    this.importAppPreferences = true,
    this.conflicts = ImportConflicts.skip,
    this.profileIds,
    this.sshKeyIds,
    this.snippetIds,
    this.knownHostSlots,
  });

  final bool mergeProfiles;
  final bool mergeSshKeys;
  final bool importSnippets;
  final bool importKnownHosts;
  final bool importTerminalSettings;
  final bool importAppPreferences;
  final ImportConflicts conflicts;

  /// Which records of a section to take, or null for all of them. An empty
  /// set is a section whose entries were all unticked, which is not the same
  /// as one that was never narrowed down.
  final Set<String>? profileIds;
  final Set<String>? sshKeyIds;
  final Set<String>? snippetIds;
  final Set<String>? knownHostSlots;
}

/// How many records of each kind this device holds.
class BackupContents {
  const BackupContents({
    required this.profiles,
    required this.sshKeys,
    required this.snippets,
    required this.knownHosts,
  });

  final int profiles;
  final int sshKeys;
  final int snippets;
  final int knownHosts;
}

/// One record inside a backup, as the import sheet lists it.
class BackupItem {
  const BackupItem({
    required this.id,
    required this.label,
    this.detail,
    this.exists = false,
  });

  final String id;
  final String label;
  final String? detail;

  /// Already on this device under the same id - what [ImportConflicts]
  /// decides the fate of.
  final bool exists;
}

class ImportPreview {
  const ImportPreview({
    required this.version,
    required this.exportedAt,
    required this.profiles,
    required this.sshKeys,
    required this.snippets,
    required this.knownHosts,
    this.groups = const [],
    required this.hasTerminalSettings,
    required this.hasAppPreferences,
    required this.wasEncrypted,
    required this.payload,
  });

  final int version;
  final DateTime exportedAt;
  final List<BackupItem> profiles;
  final List<BackupItem> sshKeys;
  final List<BackupItem> snippets;
  final List<BackupItem> knownHosts;
  final List<BackupItem> groups;
  final bool hasTerminalSettings;
  final bool hasAppPreferences;

  /// The file was passphrase-sealed and has already been opened - the import
  /// runs off the decoded payload rather than decrypting a second time.
  final bool wasEncrypted;

  /// The decoded backup itself. Only `ExportService.importBackup` reads it
  /// directly; everything else here is the trimmed-down lists above.
  final Map<String, dynamic> payload;

  int get profileCount => profiles.length;
  int get sshKeyCount => sshKeys.length;
  int get snippetCount => snippets.length;
  int get knownHostCount => knownHosts.length;
  int get groupCount => groups.length;

  int get conflictCount => [
    ...profiles,
    ...sshKeys,
    ...snippets,
    ...knownHosts,
  ].where((item) => item.exists).length;

  bool get isEmpty =>
      profiles.isEmpty &&
      sshKeys.isEmpty &&
      snippets.isEmpty &&
      knownHosts.isEmpty &&
      groups.isEmpty &&
      !hasTerminalSettings &&
      !hasAppPreferences;

  /// Whether any credential travelled in the file - what the import sheet
  /// says before writing them onto this device.
  bool get containsSecrets {
    final profiles = payload['profiles'];
    final carriesProfileSecrets =
        profiles is List &&
        profiles.any(
          (entry) =>
              entry is Map &&
              (entry['password'] != null || entry['privateKey'] != null),
        );
    return carriesProfileSecrets || sshKeys.isNotEmpty;
  }
}

/// How one section fared.
class ImportCount {
  const ImportCount({this.added = 0, this.replaced = 0, this.skipped = 0});

  final int added;
  final int replaced;
  final int skipped;

  int get changed => added + replaced;
  int get total => added + replaced + skipped;
}

class ImportResult {
  const ImportResult({
    this.profiles = const ImportCount(),
    this.sshKeys = const ImportCount(),
    this.snippets = const ImportCount(),
    this.knownHosts = const ImportCount(),
    this.groups = const ImportCount(),
    this.terminalSettings = false,
    this.appPreferences = false,
    this.profilesMissingKey = const [],
    this.profilesMissingJumpHost = const [],
  });

  final ImportCount profiles;
  final ImportCount sshKeys;
  final ImportCount snippets;
  final ImportCount knownHosts;
  final ImportCount groups;
  final bool terminalSettings;
  final bool appPreferences;

  /// Names of imported profiles whose `sshKeyId` points at a key that is not
  /// on this device - what leaving the SSH keys section out produces. The
  /// profile is kept: the key can still be imported afterwards, and dropping
  /// the profile would lose everything else on it.
  final List<String> profilesMissingKey;

  /// Same, for a `jumpHostProfileId` whose bastion profile did not come along.
  final List<String> profilesMissingJumpHost;

  int get changedRecords =>
      profiles.changed +
      sshKeys.changed +
      snippets.changed +
      knownHosts.changed +
      groups.changed;

  int get skippedRecords =>
      profiles.skipped +
      sshKeys.skipped +
      snippets.skipped +
      knownHosts.skipped +
      groups.skipped;

  bool get changedAnything =>
      changedRecords > 0 || terminalSettings || appPreferences;

  bool get hasWarnings =>
      profilesMissingKey.isNotEmpty || profilesMissingJumpHost.isNotEmpty;
}

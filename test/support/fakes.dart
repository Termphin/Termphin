import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/services/storage/profile_storage.dart';
import 'package:termphin/services/storage/snippet_storage.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';

class FakeProfileStorage extends ProfileStorage {
  FakeProfileStorage([List<SshProfile> profiles = const []])
    : profiles = List.of(profiles);

  List<SshProfile> profiles;
  int loadCount = 0;
  int addCount = 0;
  int updateCount = 0;
  int deleteCount = 0;

  @override
  Future<List<SshProfile>> loadProfiles() async {
    loadCount++;
    return List.of(profiles);
  }

  /// Makes the next [addProfile] throw, so callers can be tested for what they
  /// do when the write fails rather than only when it succeeds.
  bool failNextAdd = false;

  @override
  Future<void> addProfile(SshProfile profile) async {
    if (failNextAdd) {
      failNextAdd = false;
      throw StateError('Storage is unavailable.');
    }
    addCount++;
    profiles.add(profile);
  }

  @override
  Future<void> updateProfile(SshProfile profile) async {
    updateCount++;
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index == -1) throw StateError('Profile not found.');
    profiles[index] = profile;
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    deleteCount++;
    profiles.removeWhere((profile) => profile.id == profileId);
  }
}

class FakeGroupStorage extends GroupStorage {
  FakeGroupStorage({
    List<ProfileGroup>? initialGroups,
    FakeProfileStorage? profilesStorage,
    SshKeyStorage? keysStorage,
    SnippetStorage? snippetsStorage,
  }) : _groups = initialGroups != null
           ? List.of(initialGroups)
           : [const ProfileGroup(name: GroupStorage.defaultGroup)],
       _fakeProfiles = profilesStorage,
       super(
         profiles: profilesStorage,
         keys: keysStorage,
         snippets: snippetsStorage,
       );

  List<ProfileGroup> _groups;
  final FakeProfileStorage? _fakeProfiles;
  int loadCount = 0;
  int saveCount = 0;

  @override
  Future<List<ProfileGroup>> loadGroups() async {
    loadCount++;
    return List.of(_groups);
  }

  @override
  Future<void> saveGroups(List<ProfileGroup> newGroups) async {
    saveCount++;
    final seen = <String>{};
    for (final g in newGroups) {
      final lower = g.name.toLowerCase();
      if (!seen.add(lower)) {
        throw ArgumentError('Duplicate group: ${g.name}');
      }
    }
    _groups = List.of(newGroups);
  }

  @override
  Future<ProfileGroup> addGroup(String name, {String? colorHex}) async {
    final current = await loadGroups();
    if (current.any((g) => g.name.toLowerCase() == name.toLowerCase())) {
      throw ArgumentError('Group already exists: $name');
    }
    final created = ProfileGroup(name: name, colorHex: colorHex);
    current.add(created);
    await saveGroups(current);
    return created;
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    final current = await loadGroups();
    final index = current.indexWhere((g) => g.name == oldName);
    if (index != -1) {
      current[index] = current[index].copyWith(name: newName);
      await saveGroups(current);
    }
    if (_fakeProfiles != null) {
      for (var i = 0; i < _fakeProfiles.profiles.length; i++) {
        if (_fakeProfiles.profiles[i].group == oldName) {
          _fakeProfiles.profiles[i] = _fakeProfiles.profiles[i].copyWith(
            group: newName,
          );
        }
      }
    }
  }

  @override
  Future<void> updateGroup(
    String oldName, {
    String? name,
    String? colorHex,
    bool clearColor = false,
  }) async {
    final current = await loadGroups();
    final index = current.indexWhere((g) => g.name == oldName);
    if (index != -1) {
      final targetName = name ?? current[index].name;
      final targetColor = clearColor
          ? null
          : (colorHex ?? current[index].colorHex);
      current[index] = ProfileGroup(name: targetName, colorHex: targetColor);
      await saveGroups(current);
    }
    if (name != null && _fakeProfiles != null) {
      for (var i = 0; i < _fakeProfiles.profiles.length; i++) {
        if (_fakeProfiles.profiles[i].group == oldName) {
          _fakeProfiles.profiles[i] = _fakeProfiles.profiles[i].copyWith(
            group: name,
          );
        }
      }
    }
  }

  @override
  Future<void> deleteGroup(String name) async {
    if (name.toLowerCase() == GroupStorage.defaultGroup.toLowerCase()) return;
    final current = await loadGroups();
    current.removeWhere((g) => g.name == name);
    await saveGroups(current);
    if (_fakeProfiles != null) {
      for (var i = 0; i < _fakeProfiles.profiles.length; i++) {
        if (_fakeProfiles.profiles[i].group == name) {
          _fakeProfiles.profiles[i] = _fakeProfiles.profiles[i].copyWith(
            group: GroupStorage.defaultGroup,
          );
        }
      }
    }
  }

  Future<void> reorderGroups(int oldIndex, int newIndex) async {
    final current = await loadGroups();
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    await saveGroups(current);
  }
}

class FakeSshKeyStorage extends SshKeyStorage {
  FakeSshKeyStorage([List<SshKey> initialKeys = const []])
    : keys = List.of(initialKeys);

  List<SshKey> keys;
  int loadCount = 0;
  int saveCount = 0;
  int deleteCount = 0;
  int updateCount = 0;
  int generateEd25519Count = 0;
  int generateRsaCount = 0;
  int importCount = 0;

  @override
  Future<List<SshKey>> loadKeys() async {
    loadCount++;
    return List.of(keys);
  }

  @override
  Future<void> saveKeys(List<SshKey> newKeys) async {
    saveCount++;
    keys = List.of(newKeys);
  }

  @override
  Future<void> deleteKey(String keyId) async {
    deleteCount++;
    keys.removeWhere((k) => k.id == keyId);
  }

  @override
  Future<void> updateKey(SshKey key) async {
    updateCount++;
    final index = keys.indexWhere((k) => k.id == key.id);
    if (index == -1) throw StateError('Key not found.');
    keys[index] = key;
  }

  @override
  Future<SshKey?> getKey(String id) async {
    try {
      return keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SshKey> generateEd25519(String name, {required String group}) async {
    generateEd25519Count++;
    final key = SshKey(
      id: 'fake-ed25519-${keys.length + 1}',
      name: name,
      keyType: SshKeyType.ed25519,
      privateKeyPem:
          '-----BEGIN OPENSSH PRIVATE KEY-----\nfake-ed25519-pem\n-----END OPENSSH PRIVATE KEY-----',
      publicKeyOpenSSH:
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeEd25519Key $name',
      createdAt: DateTime.now(),
      group: group,
    );
    keys.add(key);
    return key;
  }

  @override
  Future<SshKey> generateRsa(
    String name,
    int bits, {
    required String group,
  }) async {
    generateRsaCount++;
    final keyType = bits == 4096 ? SshKeyType.rsa4096 : SshKeyType.rsa2048;
    final key = SshKey(
      id: 'fake-rsa-${keys.length + 1}',
      name: name,
      keyType: keyType,
      privateKeyPem:
          '-----BEGIN RSA PRIVATE KEY-----\nfake-rsa-pem\n-----END RSA PRIVATE KEY-----',
      publicKeyOpenSSH:
          'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDFakeRsaKey $name',
      createdAt: DateTime.now(),
      group: group,
    );
    keys.add(key);
    return key;
  }

  /// What the form handed over, so a test can tell a forwarded passphrase from
  /// one that was collected and dropped on the floor.
  String? lastImportPassphrase;

  @override
  Future<SshKey> importFromPem(
    String name,
    String pem, {
    required String group,
    String? passphrase,
  }) async {
    importCount++;
    lastImportPassphrase = passphrase;
    final key = SshKey(
      id: 'fake-imported-${keys.length + 1}',
      name: name,
      keyType: SshKeyType.ed25519,
      privateKeyPem: pem,
      publicKeyOpenSSH:
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeImportedKey $name',
      createdAt: DateTime.now(),
      group: group,
    );
    keys.add(key);
    return key;
  }
}

/// In-memory snippets.
///
/// `SnippetStorage` serialises its writes through a **static** queue over real
/// `SharedPreferences`, so a suite that resets the preference statics between
/// tests can leave a later write waiting on a turn that never comes - which
/// reads as a mutation silently not happening rather than as an error.
class FakeSnippetStorage extends SnippetStorage {
  FakeSnippetStorage([List<Snippet> snippets = const []])
    : snippets = List.of(snippets);

  List<Snippet> snippets;

  @override
  Future<List<Snippet>> loadSnippets() async {
    final sorted = List.of(snippets)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  @override
  Future<void> saveSnippets(List<Snippet> value) async {
    snippets = List.of(value);
  }

  @override
  Future<void> addSnippet(Snippet snippet) async => snippets.add(snippet);

  @override
  Future<void> updateSnippet(Snippet snippet) async {
    final index = snippets.indexWhere((item) => item.id == snippet.id);
    if (index == -1) {
      throw StateError('Snippet not found.');
    }
    snippets[index] = snippet;
  }

  @override
  Future<void> deleteSnippet(String snippetId) async {
    snippets.removeWhere((snippet) => snippet.id == snippetId);
  }
}

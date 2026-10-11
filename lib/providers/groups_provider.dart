import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_group.dart';
import '../services/storage/group_storage.dart';
import 'profiles_provider.dart';
import 'snippets_provider.dart';
import 'ssh_keys_provider.dart';

final groupStorageProvider = Provider<GroupStorage>((ref) {
  return GroupStorage(
    profiles: ref.watch(profileStorageProvider),
    keys: ref.watch(sshKeyStorageProvider),
    snippets: ref.watch(snippetStorageProvider),
  );
});

final profileGroupsProvider =
    NotifierProvider<ProfileGroupsNotifier, List<ProfileGroup>>(
      ProfileGroupsNotifier.new,
    );

class ProfileGroupsNotifier extends Notifier<List<ProfileGroup>> {
  late final GroupStorage _storage;

  @override
  List<ProfileGroup> build() {
    _storage = ref.read(groupStorageProvider);
    loadGroups();
    return const [ProfileGroup(name: GroupStorage.defaultGroup)];
  }

  Future<void> loadGroups() async {
    final groups = await _storage.loadGroups();
    if (!ref.mounted) return;
    state = groups;
  }

  Future<void> addGroup(String name, {String? colorHex}) async {
    await _storage.addGroup(name, colorHex: colorHex);
    await loadGroups();
  }

  Future<void> renameGroup(String oldName, String newName) =>
      updateGroup(oldName, name: newName);

  Future<void> updateGroup(
    String oldName, {
    String? name,
    String? colorHex,
    bool clearColor = false,
  }) async {
    await _storage.updateGroup(
      oldName,
      name: name,
      colorHex: colorHex,
      clearColor: clearColor,
    );
    await ref.read(profilesProvider.notifier).loadProfiles();
    await ref.read(snippetsProvider.notifier).loadSnippets();
    await loadGroups();
  }

  Future<void> deleteGroup(String name) async {
    await _storage.deleteGroup(name);
    await ref.read(profilesProvider.notifier).loadProfiles();
    await ref.read(snippetsProvider.notifier).loadSnippets();
    await loadGroups();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = await _storage.loadGroups();
    if (oldIndex < 0 ||
        oldIndex >= current.length ||
        newIndex < 0 ||
        newIndex >= current.length ||
        oldIndex == newIndex) {
      return;
    }
    final list = [...current];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await _storage.saveGroups(list);
    await loadGroups();
  }
}

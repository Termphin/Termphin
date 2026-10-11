import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/profile_group.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/services/storage/profile_storage.dart';
import 'package:termphin/services/storage/snippet_storage.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

void main() {
  late ProfileStorage profileStorage;
  late SshKeyStorage keyStorage;
  late SnippetStorage snippetStorage;
  late GroupStorage groupStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    profileStorage = ProfileStorage(cipher: cipherFixture());
    keyStorage = SshKeyStorage(cipher: cipherFixture());
    snippetStorage = SnippetStorage();
    groupStorage = GroupStorage(
      profiles: profileStorage,
      keys: keyStorage,
      snippets: snippetStorage,
    );
  });

  group('GroupStorage', () {
    test(
      'a deleted group does not come back on the next loadGroups(), even when a profile previously carried that name as a tag',
      () async {
        final legacyProfile = {
          'id': 'p1',
          'name': 'Old machine',
          'host': '1.2.3.4',
          'port': 22,
          'username': 'root',
          'authMethod': 'password',
          'tags': ['GhostGroup', 'Production'],
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        };
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('ssh_profiles', [jsonEncode(legacyProfile)]);
        await prefs.setStringList('profile_groups', [
          'General',
          'GhostGroup',
          'Production',
        ]);

        final initialGroups = await groupStorage.loadGroups();
        expect(
          initialGroups.map((g) => g.name),
          containsAll(['General', 'GhostGroup', 'Production']),
        );

        await groupStorage.deleteGroup('GhostGroup');

        final afterDelete = await groupStorage.loadGroups();
        expect(afterDelete.map((g) => g.name), isNot(contains('GhostGroup')));

        final freshStorage = GroupStorage(
          profiles: profileStorage,
          keys: keyStorage,
          snippets: snippetStorage,
        );
        final freshGroups = await freshStorage.loadGroups();
        expect(freshGroups.map((g) => g.name), isNot(contains('GhostGroup')));
      },
    );

    test(
      'a renamed group leaves no trace of the old name and moves its profiles, keys AND snippets',
      () async {
        final profile = profileFixture(id: 'p1', group: 'DevOps');
        await profileStorage.saveProfiles([profile]);

        final key = sshKeyFixture(id: 'k1', group: 'DevOps');
        await keyStorage.saveKeys([key]);

        final snippet = snippetFixture(id: 's1', group: 'DevOps');
        await snippetStorage.saveSnippets([snippet]);

        await groupStorage.updateGroup('DevOps', colorHex: 'FF5733');

        await groupStorage.renameGroup('DevOps', 'PlatformOps');

        final groups = await groupStorage.loadGroups();
        expect(groups.map((g) => g.name), isNot(contains('DevOps')));
        expect(groups.map((g) => g.name), contains('PlatformOps'));

        final renamedGroup = groups.firstWhere((g) => g.name == 'PlatformOps');
        expect(renamedGroup.colorHex, 'FF5733');

        final profiles = await profileStorage.loadProfiles();
        expect(profiles.single.group, 'PlatformOps');

        final keys = await keyStorage.loadKeys();
        expect(keys.single.group, 'PlatformOps');

        final snippets = await snippetStorage.loadSnippets();
        expect(snippets.single.group, 'PlatformOps');
      },
    );

    test(
      'deleteGroup reassigns profiles, keys and snippets to General',
      () async {
        final profile = profileFixture(id: 'p1', group: 'ToRetire');
        await profileStorage.saveProfiles([profile]);

        final key = sshKeyFixture(id: 'k1', group: 'ToRetire');
        await keyStorage.saveKeys([key]);

        final snippet = snippetFixture(id: 's1', group: 'ToRetire');
        await snippetStorage.saveSnippets([snippet]);

        await groupStorage.deleteGroup('ToRetire');

        final groups = await groupStorage.loadGroups();
        expect(groups.map((g) => g.name), isNot(contains('ToRetire')));

        final profiles = await profileStorage.loadProfiles();
        expect(profiles.single.group, 'General');

        final keys = await keyStorage.loadKeys();
        expect(keys.single.group, 'General');

        final snippets = await snippetStorage.loadSnippets();
        expect(snippets.single.group, 'General');
      },
    );

    test('the first load adopts groups already standing on records', () async {
      await profileStorage.saveProfiles([
        profileFixture(id: 'p1', group: 'Prod'),
      ]);
      await keyStorage.saveKeys([sshKeyFixture(id: 'k1', group: 'Bastion')]);
      await snippetStorage.saveSnippets([
        snippetFixture(id: 's1', group: 'Ops'),
      ]);

      final names = (await groupStorage.loadGroups()).map((g) => g.name);
      expect(names, containsAll(['General', 'Prod', 'Bastion', 'Ops']));
    });

    test('deleteGroup("General") is a no-op', () async {
      await groupStorage.deleteGroup('General');
      final groups = await groupStorage.loadGroups();
      expect(groups.map((g) => g.name), contains('General'));

      await groupStorage.deleteGroup('general');
      final groups2 = await groupStorage.loadGroups();
      expect(groups2.map((g) => g.name), contains('General'));
    });

    test(
      'case-insensitive duplicates are rejected by saveGroups and addGroup',
      () async {
        await groupStorage.addGroup('Alpha');

        await groupStorage.addGroup('alpha');
        await groupStorage.addGroup('ALPHA');
        expect(
          (await groupStorage.loadGroups()).where(
            (g) => g.name.toLowerCase() == 'alpha',
          ),
          hasLength(1),
        );

        expect(
          () => groupStorage.saveGroups([
            const ProfileGroup(name: 'Beta'),
            const ProfileGroup(name: 'beta'),
          ]),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'a colour survives a save/load round trip, and a group with no colour reads back null',
      () async {
        await groupStorage.addGroup('Colorful', colorHex: '4DA3FF');
        await groupStorage.addGroup('Monochrome');

        final freshStorage = GroupStorage(
          profiles: profileStorage,
          keys: keyStorage,
          snippets: snippetStorage,
        );

        final loaded = await freshStorage.loadGroups();
        final colorful = loaded.firstWhere((g) => g.name == 'Colorful');
        final mono = loaded.firstWhere((g) => g.name == 'Monochrome');

        expect(colorful.colorHex, '4DA3FF');
        expect(mono.colorHex, isNull);
      },
    );

    test(
      'renaming a group rewrites a record stored with a different letter case',
      () async {
        await groupStorage.addGroup('DevOps');

        final profile = profileFixture(id: 'p1', group: 'devops');
        await profileStorage.saveProfiles([profile]);

        final key = sshKeyFixture(id: 'k1', group: 'DEVOPS');
        await keyStorage.saveKeys([key]);

        final snippet = snippetFixture(id: 's1', group: 'DevOps');
        await snippetStorage.saveSnippets([snippet]);

        await groupStorage.renameGroup('DevOps', 'PlatformOps');

        final profiles = await profileStorage.loadProfiles();
        expect(profiles.single.group, 'PlatformOps');

        final keys = await keyStorage.loadKeys();
        expect(keys.single.group, 'PlatformOps');

        final snippets = await snippetStorage.loadSnippets();
        expect(snippets.single.group, 'PlatformOps');
      },
    );

    test(
      'deleting a group reassigns a record stored with a different letter case to the default group',
      () async {
        await groupStorage.addGroup('ToRetire');

        final profile = profileFixture(id: 'p1', group: 'toretire');
        await profileStorage.saveProfiles([profile]);

        final key = sshKeyFixture(id: 'k1', group: 'TORETIRE');
        await keyStorage.saveKeys([key]);

        final snippet = snippetFixture(id: 's1', group: 'ToRetire');
        await snippetStorage.saveSnippets([snippet]);

        await groupStorage.deleteGroup('ToRetire');

        final profiles = await profileStorage.loadProfiles();
        expect(profiles.single.group, 'General');

        final keys = await keyStorage.loadKeys();
        expect(keys.single.group, 'General');

        final snippets = await snippetStorage.loadSnippets();
        expect(snippets.single.group, 'General');
      },
    );
  });
}

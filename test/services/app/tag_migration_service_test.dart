import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/services/app/tag_migration_service.dart';
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
  late TagMigrationService migrationService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TagMigrationService.debugForceOverride = false;
    profileStorage = ProfileStorage(cipher: cipherFixture());
    keyStorage = SshKeyStorage(cipher: cipherFixture());
    snippetStorage = SnippetStorage();
    groupStorage = GroupStorage(
      profiles: profileStorage,
      keys: keyStorage,
      snippets: snippetStorage,
    );
    migrationService = TagMigrationService(
      profiles: profileStorage,
      snippets: snippetStorage,
      groups: groupStorage,
    );
  });

  Map<String, dynamic> legacyProfileJson({
    required String id,
    required String name,
    List<String>? tags,
  }) => {
    'id': id,
    'name': name,
    'host': '192.168.1.1',
    'port': 22,
    'username': 'root',
    'authMethod': 'password',
    'tags': ?tags,
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
  };

  Map<String, dynamic> legacySnippetJson({
    required String id,
    required String name,
    List<String>? tags,
  }) => {
    'id': id,
    'name': name,
    'command': 'uptime',
    'tags': ?tags,
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
  };

  group('TagMigrationService', () {
    test(
      'detect() finds nothing on a fresh install and isPending() is false',
      () async {
        final plan = await migrationService.detect();
        expect(plan.isEmpty, isTrue);
        expect(plan.tags, isEmpty);
        expect(plan.recordCount, 0);
        expect(await migrationService.isPending(), isFalse);
      },
    );

    test(
      'detect() on seeded raw preferences reports each distinct tag with the right counts, most-used first',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('ssh_profiles', [
          jsonEncode(
            legacyProfileJson(id: 'p1', name: 'Web 1', tags: ['prod', 'web']),
          ),
          jsonEncode(
            legacyProfileJson(id: 'p2', name: 'Web 2', tags: ['prod', 'web']),
          ),
          jsonEncode(
            legacyProfileJson(id: 'p3', name: 'DB 1', tags: ['prod', 'db']),
          ),
          jsonEncode(legacyProfileJson(id: 'p4', name: 'No tags', tags: [])),
        ]);
        await prefs.setStringList('snippets', [
          jsonEncode(
            legacySnippetJson(id: 's1', name: 'Deploy', tags: ['prod', 'ops']),
          ),
          jsonEncode(
            legacySnippetJson(id: 's2', name: 'Status', tags: ['ops']),
          ),
          jsonEncode(legacySnippetJson(id: 's3', name: 'Plain', tags: null)),
        ]);

        final plan = await migrationService.detect();
        expect(plan.isEmpty, isFalse);
        expect(plan.recordCount, 5);
        expect(plan.tags.length, 4);

        expect(plan.tags[0].name, 'prod');
        expect(plan.tags[0].profileCount, 3);
        expect(plan.tags[0].snippetCount, 1);
        expect(plan.tags[0].totalCount, 4);

        final opsOrWeb = [plan.tags[1].name, plan.tags[2].name];
        expect(opsOrWeb, containsAll(['web', 'ops']));

        expect(plan.tags[3].name, 'db');
        expect(plan.tags[3].profileCount, 1);
        expect(plan.tags[3].snippetCount, 0);
        expect(plan.tags[3].totalCount, 1);

        expect(await migrationService.isPending(), isTrue);
      },
    );

    test(
      'apply with every tag kept creates those groups and puts each record in its first tag',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('ssh_profiles', [
          jsonEncode(
            legacyProfileJson(id: 'p1', name: 'Alpha', tags: ['web', 'prod']),
          ),
          jsonEncode(
            legacyProfileJson(id: 'p2', name: 'Beta', tags: ['prod', 'web']),
          ),
        ]);
        await prefs.setStringList('snippets', [
          jsonEncode(
            legacySnippetJson(id: 's1', name: 'Restart', tags: ['ops', 'prod']),
          ),
        ]);
        final key = sshKeyFixture(id: 'k1', name: 'Key 1');
        await keyStorage.saveKeys([key]);

        await migrationService.apply({'web', 'prod', 'ops'});

        final groups = await groupStorage.loadGroups();
        final groupNames = groups.map((g) => g.name).toList();
        expect(groupNames.first, GroupStorage.defaultGroup);
        expect(groupNames, containsAll(['General', 'web', 'prod', 'ops']));

        final profiles = await profileStorage.loadProfiles();
        final p1 = profiles.firstWhere((p) => p.id == 'p1');
        final p2 = profiles.firstWhere((p) => p.id == 'p2');
        expect(p1.group, 'web');
        expect(p2.group, 'prod');

        final snippets = await snippetStorage.loadSnippets();
        final s1 = snippets.firstWhere((s) => s.id == 's1');
        expect(s1.group, 'ops');

        final keys = await keyStorage.loadKeys();
        expect(keys.first.group, GroupStorage.defaultGroup);

        for (final p in profiles) {
          expect(groupNames, contains(p.group));
        }
        for (final k in keys) {
          expect(groupNames, contains(k.group));
        }
        for (final s in snippets) {
          expect(groupNames, contains(s.group));
        }

        expect(prefs.getBool(TagMigrationService.doneKey), isTrue);
        expect(prefs.getBool(GroupStorage.migratedKey), isTrue);
        expect(await migrationService.isPending(), isFalse);
      },
    );

    test(
      'apply with a subset puts a record whose first tag was dropped into its first kept tag, and a record with no kept tags into General',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('ssh_profiles', [
          jsonEncode(
            legacyProfileJson(id: 'p1', name: 'Alpha', tags: ['web', 'prod']),
          ),
          jsonEncode(legacyProfileJson(id: 'p2', name: 'Beta', tags: ['web'])),
        ]);
        await prefs.setStringList('snippets', [
          jsonEncode(
            legacySnippetJson(
              id: 's1',
              name: 'Run',
              tags: ['deprecated', 'ops'],
            ),
          ),
          jsonEncode(
            legacySnippetJson(id: 's2', name: 'Old', tags: ['deprecated']),
          ),
        ]);

        await migrationService.apply({'prod', 'ops'});

        final groups = await groupStorage.loadGroups();
        final groupNames = groups.map((g) => g.name).toList();
        expect(groupNames, containsAll(['General', 'prod', 'ops']));
        expect(groupNames, isNot(contains('web')));
        expect(groupNames, isNot(contains('deprecated')));

        final profiles = await profileStorage.loadProfiles();
        final p1 = profiles.firstWhere((p) => p.id == 'p1');
        final p2 = profiles.firstWhere((p) => p.id == 'p2');
        expect(p1.group, 'prod');
        expect(p2.group, GroupStorage.defaultGroup);

        final snippets = await snippetStorage.loadSnippets();
        final s1 = snippets.firstWhere((s) => s.id == 's1');
        final s2 = snippets.firstWhere((s) => s.id == 's2');
        expect(s1.group, 'ops');
        expect(s2.group, GroupStorage.defaultGroup);

        for (final p in profiles) {
          expect(groupNames, contains(p.group));
        }
        for (final s in snippets) {
          expect(groupNames, contains(s.group));
        }
      },
    );

    test('skip creates no groups and leaves every record in General', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('ssh_profiles', [
        jsonEncode(
          legacyProfileJson(id: 'p1', name: 'Alpha', tags: ['web', 'prod']),
        ),
      ]);
      await prefs.setStringList('snippets', [
        jsonEncode(legacySnippetJson(id: 's1', name: 'Restart', tags: ['ops'])),
      ]);

      await migrationService.skip();

      final groups = await groupStorage.loadGroups();
      expect(groups.map((g) => g.name).toList(), [GroupStorage.defaultGroup]);

      final profiles = await profileStorage.loadProfiles();
      expect(profiles.first.group, GroupStorage.defaultGroup);

      final snippets = await snippetStorage.loadSnippets();
      expect(snippets.first.group, GroupStorage.defaultGroup);

      final keys = await keyStorage.loadKeys();
      for (final k in keys) {
        expect(k.group, GroupStorage.defaultGroup);
      }

      final groupNames = groups.map((g) => g.name).toList();
      for (final p in profiles) {
        expect(groupNames, contains(p.group));
      }
      for (final s in snippets) {
        expect(groupNames, contains(s.group));
      }

      expect(prefs.getBool(TagMigrationService.doneKey), isTrue);
      expect(prefs.getBool(GroupStorage.migratedKey), isTrue);
      expect(await migrationService.isPending(), isFalse);
    });

    test(
      'both paths set the done flag so isPending() is false afterwards, and set GroupStorage seed flag so the group list is not auto-repopulated',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('ssh_profiles', [
          jsonEncode(
            legacyProfileJson(id: 'p1', name: 'Alpha', tags: ['GhostGroup']),
          ),
        ]);

        await migrationService.skip();

        expect(prefs.getBool(TagMigrationService.doneKey), isTrue);
        expect(prefs.getBool(GroupStorage.migratedKey), isTrue);
        expect(await migrationService.isPending(), isFalse);

        final freshStorage = GroupStorage(
          profiles: profileStorage,
          keys: keyStorage,
          snippets: snippetStorage,
        );
        final freshGroups = await freshStorage.loadGroups();
        expect(freshGroups.map((g) => g.name), isNot(contains('GhostGroup')));
      },
    );
  });

  group('forced for testing', () {
    setUp(() => TagMigrationService.debugForceOverride = true);
    tearDown(() => TagMigrationService.debugForceOverride = false);

    test('a device with no tags is offered a sample plan', () async {
      final plan = await migrationService.detect();
      expect(plan.isSample, isTrue);
      expect(plan.tags.map((c) => c.name), contains('production'));
      expect(await migrationService.isPending(), isTrue);
    });

    test('answering a sample never touches real data', () async {
      await groupStorage.saveGroups([
        const ProfileGroup(name: GroupStorage.defaultGroup),
        const ProfileGroup(name: 'Mine', colorHex: '4DA3FF'),
      ]);
      await profileStorage.saveProfiles([
        profileFixture(id: 'p1', group: 'Mine'),
      ]);

      await migrationService.apply({'production'});

      final groups = await groupStorage.loadGroups();
      expect(groups.map((g) => g.name), containsAll(['Mine', 'production']));
      expect(groups.firstWhere((g) => g.name == 'Mine').colorHex, '4DA3FF');
      expect((await profileStorage.loadProfiles()).single.group, 'Mine');
    });

    test('skipping a sample changes nothing at all', () async {
      await profileStorage.saveProfiles([
        profileFixture(id: 'p1', group: 'Mine'),
      ]);

      await migrationService.skip();

      expect((await profileStorage.loadProfiles()).single.group, 'Mine');
    });

    test('the dialog is re-offered on the next launch', () async {
      await migrationService.apply({'production'});
      expect(await migrationService.isPending(), isTrue);
    });
  });
}

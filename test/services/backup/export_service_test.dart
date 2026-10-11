import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/known_host.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/services/backup/backup_crypto.dart';
import 'package:termphin/services/backup/export_service.dart';
import 'package:termphin/services/completion/command_completion.dart';
import 'package:termphin/services/settings/editor_settings.dart';
import 'package:termphin/services/settings/sidebar_settings.dart';
import 'package:termphin/services/settings/tab_bar_settings.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/settings/toolbar_layout.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/services/storage/known_hosts_store.dart';
import 'package:termphin/services/storage/profile_storage.dart';
import 'package:termphin/services/storage/snippet_storage.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';
import 'package:termphin/widgets/terminal/special_keys_toolbar.dart';

import '../../support/fixtures.dart';
import '../../support/secure_storage_channel.dart';

void main() {
  late ExportService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    service = ExportService();
  });

  test(
    'exports selected data while redacting profile secrets by default',
    () async {
      final profile = profileFixture(
        password: 'password',
        privateKey: 'private-key',
      );
      await ProfileStorage().saveProfiles([profile]);
      await SshKeyStorage().saveKeys([sshKeyFixture()]);

      final json =
          jsonDecode(await service.exportToJson(const ExportOptions()))
              as Map<String, dynamic>;
      final exportedProfile =
          (json['profiles'] as List).single as Map<String, dynamic>;

      expect(json['version'], kBackupVersion);
      expect(json['format'], kBackupFormat);
      expect(exportedProfile.containsKey('password'), isFalse);
      expect(exportedProfile.containsKey('privateKey'), isFalse);
      expect(json['sshKeys'], hasLength(1));
      expect(json['terminalSettings'], isA<Map<String, dynamic>>());
      expect(
        (json['terminalSettings'] as Map<String, dynamic>)['fontFamily'],
        terminalSettings.fontFamily.fallback,
      );
      expect(json['appPreferences'], isA<Map<String, dynamic>>());
    },
  );

  test('can include secrets and omit optional sections', () async {
    await ProfileStorage().saveProfiles([
      profileFixture(password: 'password', privateKey: 'private-key'),
    ]);

    final json =
        jsonDecode(
              await service.exportToJson(
                const ExportOptions(
                  includePasswords: true,
                  includeInlinePrivateKeys: true,
                  includeSshKeys: false,
                  includeTerminalSettings: false,
                  includeAppPreferences: false,
                ),
              ),
            )
            as Map<String, dynamic>;
    final profile = (json['profiles'] as List).single as Map<String, dynamic>;

    expect(profile['password'], 'password');
    expect(profile['privateKey'], 'private-key');
    expect(json.containsKey('sshKeys'), isFalse);
    expect(json.containsKey('terminalSettings'), isFalse);
    expect(json.containsKey('appPreferences'), isFalse);
  });

  test('inspects a backup and lists what is in it', () async {
    final preview = await service.inspect(
      jsonEncode({
        'format': kBackupFormat,
        'version': 2,
        'exportedAt': '2026-01-02T03:04:05.000Z',
        'profiles': [
          profileFixture(id: 'a').toJson(),
          profileFixture(id: 'b').toJson(),
        ],
        'sshKeys': [sshKeyFixture().toJson()],
        'terminalSettings': <String, dynamic>{},
      }),
    );

    expect(preview.version, 2);
    expect(preview.profileCount, 2);
    expect(preview.sshKeyCount, 1);
    expect(preview.hasTerminalSettings, isTrue);
    expect(preview.hasAppPreferences, isFalse);
    expect(preview.profiles.first.detail, 'deploy@example.com');
  });

  test('a file that is not a backup is refused rather than imported', () async {
    for (final raw in [
      'not-json',
      jsonEncode({'name': 'some-package', 'dependencies': <String, String>{}}),
      jsonEncode([1, 2, 3]),
    ]) {
      await expectLater(
        service.inspect(raw),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.notABackup,
          ),
        ),
      );
    }
  });

  test('a backup from a newer build is refused, not half-read', () async {
    await expectLater(
      service.inspect(
        jsonEncode({
          'format': kBackupFormat,
          'version': kBackupVersion + 1,
          'profiles': [profileFixture().toJson()],
        }),
      ),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.unsupportedVersion,
        ),
      ),
    );
    expect(await ProfileStorage().loadProfiles(), isEmpty);
  });

  test('a file written before the format marker is still ours', () async {
    final preview = await service.inspect(
      jsonEncode({
        'version': 2,
        'profiles': [profileFixture().toJson()],
      }),
    );

    expect(preview.profileCount, 1);
  });

  test('marks the records this device already has', () async {
    await ProfileStorage().saveProfiles([profileFixture(id: 'here')]);

    final preview = await service.inspect(
      jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'profiles': [
          profileFixture(id: 'here').toJson(),
          profileFixture(id: 'elsewhere').toJson(),
        ],
      }),
    );

    expect(preview.conflictCount, 1);
    expect(
      preview.profiles.singleWhere((item) => item.id == 'here').exists,
      isTrue,
    );
  });

  test('imports new records without duplicating existing IDs', () async {
    final existingProfile = profileFixture(id: 'existing');
    final newProfile = profileFixture(id: 'new');
    final existingKey = sshKeyFixture(id: 'existing-key');
    final newKey = sshKeyFixture(id: 'new-key');
    await ProfileStorage().saveProfiles([existingProfile]);
    await SshKeyStorage().saveKeys([existingKey]);

    final result = await service.importFromJson(
      jsonEncode({
        'version': 2,
        'profiles': [existingProfile.toJson(), newProfile.toJson()],
        'sshKeys': [existingKey.toJson(), newKey.toJson()],
      }),
      const ImportOptions(),
    );

    expect(result.profiles.added, 1);
    expect(result.profiles.skipped, 1);
    expect(result.sshKeys.added, 1);
    expect(result.sshKeys.skipped, 1);
    expect(result.changedRecords, 2);

    expect(
      (await ProfileStorage().loadProfiles())
          .map((profile) => profile.id)
          .toSet(),
      {'existing', 'new'},
    );
    expect((await SshKeyStorage().loadKeys()).map((key) => key.id).toSet(), {
      'existing-key',
      'new-key',
    });
  });

  test('imports terminal settings and application preferences', () async {
    await service.importFromJson(
      jsonEncode({
        'version': 2,
        'terminalSettings': {
          'schemeId': 'nord',
          'fontFamily': 'UbuntuMonoNerdFontMono',
          'fontSize': 17.0,
          'lineHeight': 1.3,
          'sidePadding': 8.0,
          'cursorStyle': 'underline',
          'cursorBlink': false,
          'touchMouseWheel': true,
          'predictiveEcho': false,
        },
        'appPreferences': {
          'toolbarOrder': ['esc', 'esc', 'invalid'],
          'sftpShowHidden': true,
          'sftpFollowTerminal': false,
          'editorWordWrap': false,
          'editorFontSize': 16.5,
          'editorFontFamily': 'FiraCodeNerdFontMono',
          'editorLineNumbers': false,
          'editorLineHeight': 1.8,
          'editorTabWidth': 4,
          'sidebarCollapsed': true,
          'commandSuggestions': false,
          'tabBarPosition': 'bottom',
        },
      }),
      const ImportOptions(),
    );

    final settings = terminalSettings;
    await settings.load();
    final prefs = await SharedPreferences.getInstance();
    expect(settings.scheme.value, 'nord');
    expect(settings.fontFamily.value, 'UbuntuMonoNerdFontMono');
    expect(settings.lineHeight.value, 1.3);
    expect(settings.sidePadding.value, 8);
    expect(settings.cursorStyle.value, 'underline');
    expect(settings.cursorBlink.value, isFalse);
    expect(settings.predictiveEcho.value, isFalse);
    expect(prefs.getDouble(kTerminalFontSizePrefsKey), 17);
    expect(
      prefs.getStringList(kToolbarOrderPrefsKey),
      normalizeToolbarOrder(['esc', 'esc', 'invalid']),
    );
    expect(prefs.getBool('sftp_show_hidden'), isTrue);
    expect(prefs.getBool('sftp_follow_terminal'), isFalse);
    expect(prefs.getBool('editor_word_wrap'), isFalse);
    expect(editorSettings.wordWrap.value, isFalse);
    expect(editorSettings.fontSize.value, 16.5);
    expect(editorSettings.fontFamily.value, 'FiraCodeNerdFontMono');
    expect(editorSettings.lineNumbers.value, isFalse);
    expect(editorSettings.lineHeight.value, 1.8);
    expect(editorSettings.tabWidth.value, 4);
    expect(sidebarCollapsedSetting.value, isTrue);
    expect(commandSuggestionsSetting.value, isFalse);
    expect(tabBarPositionSetting.value, TabBarPosition.bottom);
  });

  test('carries every toolbar profile through an export', () async {
    await toolbarSettings.load();
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(
        ToolbarProfile(
          id: 'vim',
          name: 'Vim',
          layout: ToolbarLayout.blank.copyWith(rows: 3),
        ),
      ),
    );

    final exported =
        jsonDecode(await service.exportToJson(const ExportOptions()))
            as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await toolbarSettings.load();
    await service.importFromJson(jsonEncode(exported), const ImportOptions());
    await toolbarSettings.load();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.profiles.map((p) => p.id), containsAll(['vim']));
    expect(profiles.activeId, 'vim');
    expect(profiles.active.layout.rows, 3);
    expect(toolbarSettings.layout.value.rows, 3);
  });

  test('a toolbar switched off comes back off', () async {
    await toolbarSettings.load();
    await toolbarSettings.enabled.set(false);

    final exported = await service.exportToJson(const ExportOptions());
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await toolbarSettings.load();
    expect(toolbarSettings.enabled.value, isTrue);

    await service.importFromJson(exported, const ImportOptions());
    await toolbarSettings.load();
    expect(toolbarSettings.enabled.value, isFalse);
  });

  test('a round trip keeps fallback addresses and their order', () async {
    final profile = profileFixture(
      fallbackHosts: ['10.0.0.1', 'vpn.example.com:2222'],
      lastGoodHost: 'vpn.example.com:2222',
      mainHostFirst: false,
    );
    await ProfileStorage().saveProfiles([profile]);
    final exported = await service.exportToJson(const ExportOptions());
    await ProfileStorage().saveProfiles([]);

    await service.importFromJson(exported, const ImportOptions());

    final restored = (await ProfileStorage().loadProfiles()).single;
    expect(restored.fallbackHosts, profile.fallbackHosts);
    expect(restored.lastGoodHost, profile.lastGoodHost);
    expect(restored.mainHostFirst, isFalse);
  });

  test('an imported profile replaces the one it shares an id with', () async {
    await toolbarSettings.load();
    await saveToolbarProfiles(
      ToolbarProfiles(
        profiles: [
          ToolbarProfile(
            id: kDefaultToolbarProfileId,
            name: '',
            layout: ToolbarLayout.defaults,
          ),
          ToolbarProfile(id: 'kept', name: 'Kept', layout: ToolbarLayout.blank),
        ],
      ),
    );

    await service.importFromJson(
      jsonEncode({
        'version': 2,
        'appPreferences': {
          'toolbarProfiles': [
            {
              'id': 'kept',
              'name': 'Imported',
              'order': <String>[],
              'columns': 5,
              'rows': 2,
              'pages': 1,
              'buttonHeight': 40.0,
            },
          ],
          'toolbarActiveProfile': 'kept',
        },
      }),
      const ImportOptions(),
    );
    await toolbarSettings.load();

    final profiles = toolbarSettings.profiles.value;
    expect(profiles.profiles, hasLength(2));
    expect(
      profiles.profiles.firstWhere((p) => p.id == 'kept').name,
      'Imported',
    );
    expect(profiles.activeId, 'kept');
  });

  test('respects disabled import sections', () async {
    final profile = profileFixture();
    await service.importFromJson(
      jsonEncode({
        'version': 2,
        'profiles': [profile.toJson()],
        'terminalSettings': {'schemeId': 'dracula'},
      }),
      const ImportOptions(mergeProfiles: false, importTerminalSettings: false),
    );

    expect(await ProfileStorage().loadProfiles(), isEmpty);
    expect((await terminalSettings.scheme.load()), 'default');
  });

  test('replace overwrites the record it shares an id with', () async {
    await ProfileStorage().saveProfiles([profileFixture(name: 'Old')]);

    final result = await service.importFromJson(
      jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'profiles': [profileFixture(name: 'New').toJson()],
      }),
      const ImportOptions(conflicts: ImportConflicts.replace),
    );

    expect(result.profiles.replaced, 1);
    expect(result.profiles.added, 0);
    expect((await ProfileStorage().loadProfiles()).single.name, 'New');
  });

  test('takes only the records that were ticked', () async {
    final result = await service.importFromJson(
      jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'profiles': [
          profileFixture(id: 'wanted').toJson(),
          profileFixture(id: 'unwanted').toJson(),
        ],
      }),
      const ImportOptions(profileIds: {'wanted'}),
    );

    expect(result.profiles.added, 1);
    expect(result.profiles.skipped, 1);
    expect((await ProfileStorage().loadProfiles()).map((p) => p.id), [
      'wanted',
    ]);
  });

  test('carries snippets and known hosts across', () async {
    final snippet = Snippet(
      id: 'snippet-1',
      name: 'Tail log',
      command: 'tail -f /var/log/syslog',
      createdAt: DateTime.utc(2026, 3, 4),
    );
    await SnippetStorage().saveSnippets([snippet]);
    await KnownHostsStore.instance.trust(
      KnownHost(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:abc',
        addedAt: DateTime.utc(2026, 3, 4),
      ),
    );

    final exported = await service.exportToJson(
      const ExportOptions(includeKnownHosts: true),
    );

    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    final result = await service.importFromJson(
      exported,
      const ImportOptions(),
    );

    expect(result.snippets.added, 1);
    expect(result.knownHosts.added, 1);
    expect((await SnippetStorage().loadSnippets()).single.name, 'Tail log');
    expect(
      (await KnownHostsStore.instance.entries()).single.fingerprint,
      'SHA256:abc',
    );
  });

  test('reports a profile whose key did not come with it', () async {
    final result = await service.importFromJson(
      jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'profiles': [
          profileFixture(
            name: 'Bastion user',
            sshKeyId: 'missing-key',
            jumpHostProfileId: 'missing-profile',
          ).toJson(),
        ],
        'sshKeys': [sshKeyFixture(id: 'other-key').toJson()],
      }),
      const ImportOptions(mergeSshKeys: false),
    );

    expect(result.profilesMissingKey, ['Bastion user']);
    expect(result.profilesMissingJumpHost, ['Bastion user']);
  });

  test('a key passphrase travels with the secrets, not always', () async {
    await ProfileStorage().saveProfiles([
      profileFixture(privateKey: 'private-key', passphrase: 'key-passphrase'),
    ]);

    final redacted =
        jsonDecode(await service.exportToJson(const ExportOptions()))
            as Map<String, dynamic>;
    final withSecrets =
        jsonDecode(
              await service.exportToJson(
                const ExportOptions(includeInlinePrivateKeys: true),
              ),
            )
            as Map<String, dynamic>;

    expect(
      ((redacted['profiles'] as List).single as Map)['passphrase'],
      isNull,
    );
    expect(
      ((withSecrets['profiles'] as List).single as Map)['passphrase'],
      'key-passphrase',
    );
  });

  test('a passphrase-sealed backup opens only with its passphrase', () async {
    await ProfileStorage().saveProfiles([profileFixture(id: 'sealed')]);

    final sealed = await service.exportToJson(
      const ExportOptions(),
      passphrase: 'correct horse',
    );

    expect(sealed.contains('sealed'), isFalse);
    await expectLater(
      service.inspect(sealed),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.passphraseRequired,
        ),
      ),
    );
    await expectLater(
      service.inspect(sealed, passphrase: 'wrong horse'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.wrongPassphrase,
        ),
      ),
    );

    final preview = await service.inspect(sealed, passphrase: 'correct horse');
    expect(preview.wasEncrypted, isTrue);
    expect(preview.profiles.single.id, 'sealed');
  });

  test('an export of nothing is reported as empty', () {
    const nothing = ExportOptions(
      includeProfiles: false,
      includeSshKeys: false,
      includeSnippets: false,
      includeKnownHosts: false,
      includeTerminalSettings: false,
      includeAppPreferences: false,
    );

    expect(nothing.isEmpty, isTrue);
    expect(nothing.containsSecrets, isFalse);
    expect(const ExportOptions().isEmpty, isFalse);
    expect(const ExportOptions().containsSecrets, isTrue);
  });

  test('a round trip preserves group names, colours and order', () async {
    final groupStorage = GroupStorage();
    await groupStorage.saveGroups([
      const ProfileGroup(name: 'General'),
      const ProfileGroup(name: 'Production', colorHex: 'FF0000'),
      const ProfileGroup(name: 'Staging', colorHex: 'FF9900'),
      const ProfileGroup(name: 'Development'),
    ]);

    final exported = await service.exportToJson(const ExportOptions());

    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    final result = await service.importFromJson(
      exported,
      const ImportOptions(),
    );

    final loaded = await groupStorage.loadGroups();
    expect(loaded.map((g) => g.name).toList(), [
      'General',
      'Production',
      'Staging',
      'Development',
    ]);
    expect(loaded.map((g) => g.colorHex).toList(), [
      null,
      'FF0000',
      'FF9900',
      null,
    ]);
    expect(result.groups.added, 3);
    expect(result.groups.skipped, 1);
  });

  test('a round trip keeps the order when General is not first', () async {
    final groupStorage = GroupStorage();
    await groupStorage.saveGroups([
      const ProfileGroup(name: 'Production'),
      const ProfileGroup(name: 'General'),
      const ProfileGroup(name: 'Staging'),
    ]);

    final exported = await service.exportToJson(const ExportOptions());

    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    await service.importFromJson(exported, const ImportOptions());

    final loaded = await groupStorage.loadGroups();
    expect(loaded.map((g) => g.name).toList(), [
      'Production',
      'General',
      'Staging',
    ]);
  });

  test(
    'importing onto a device with groups follows the file order and keeps device-only groups after it',
    () async {
      final groupStorage = GroupStorage();
      await groupStorage.saveGroups([
        const ProfileGroup(name: 'General'),
        const ProfileGroup(name: 'Local', colorHex: '333333'),
        const ProfileGroup(name: 'Staging', colorHex: '111111'),
      ]);

      final file = jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'groups': [
          const ProfileGroup(name: 'Production').toJson(),
          const ProfileGroup(name: 'staging', colorHex: '999999').toJson(),
          const ProfileGroup(name: 'General').toJson(),
        ],
      });

      await service.importFromJson(file, const ImportOptions());

      final loaded = await groupStorage.loadGroups();
      expect(loaded.map((g) => g.name).toList(), [
        'Production',
        'Staging',
        'General',
        'Local',
      ]);
      expect(loaded[1].colorHex, '111111');
    },
  );

  test(
    'importing a file whose group already exists on the device does not overwrite its colour',
    () async {
      final groupStorage = GroupStorage();
      await groupStorage.saveGroups([
        const ProfileGroup(name: 'General'),
        const ProfileGroup(name: 'Production', colorHex: '111111'),
      ]);

      final file = jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'groups': [
          const ProfileGroup(name: 'Production', colorHex: '999999').toJson(),
          const ProfileGroup(name: 'Staging', colorHex: '222222').toJson(),
        ],
      });

      final result = await service.importFromJson(file, const ImportOptions());

      final loaded = await groupStorage.loadGroups();
      final prod = loaded.firstWhere((g) => g.name == 'Production');
      final staging = loaded.firstWhere((g) => g.name == 'Staging');

      expect(prod.colorHex, '111111');
      expect(staging.colorHex, '222222');
      expect(result.groups.skipped, 1);
      expect(result.groups.added, 1);
    },
  );

  test(
    'importing a record whose group is missing from both the file and the device creates that group rather than leaving a dangling reference',
    () async {
      final groupStorage = GroupStorage();
      final groupsBefore = await groupStorage.loadGroups();
      expect(groupsBefore.any((g) => g.name == 'Isolated'), isFalse);

      final file = jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'groups': [const ProfileGroup(name: 'General').toJson()],
        'profiles': [
          profileFixture(
            id: 'orphan',
            name: 'Orphan Profile',
            group: 'Isolated',
          ).toJson(),
        ],
      });

      final result = await service.importFromJson(file, const ImportOptions());

      final groupsAfter = await groupStorage.loadGroups();
      final created = groupsAfter.firstWhere((g) => g.name == 'Isolated');
      expect(created.colorHex, isNull);
      expect(result.groups.added, 1);

      final imported = (await ProfileStorage().loadProfiles()).single;
      expect(imported.group, 'Isolated');
    },
  );

  test(
    'a version-3 file (no groups key, profiles carrying tags) imports with every record landing in a real group',
    () async {
      final groupStorage = GroupStorage();

      final file = jsonEncode({
        'format': kBackupFormat,
        'version': 3,
        'profiles': [
          {
            'id': 'p1',
            'name': 'Web Server',
            'host': 'web.example.com',
            'port': 22,
            'username': 'admin',
            'authMethod': 'password',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'tags': ['WebFleet'],
          },
          {
            'id': 'p2',
            'name': 'Db Server',
            'host': 'db.example.com',
            'port': 22,
            'username': 'admin',
            'authMethod': 'password',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'tags': <String>[],
          },
        ],
      });

      final result = await service.importFromJson(file, const ImportOptions());

      expect(result.profiles.added, 2);
      expect(result.groups.added, 1);

      final groups = await groupStorage.loadGroups();
      expect(groups.any((g) => g.name == 'WebFleet'), isTrue);
      expect(groups.any((g) => g.name == 'General'), isTrue);

      final profiles = await ProfileStorage().loadProfiles();
      final p1 = profiles.firstWhere((p) => p.id == 'p1');
      final p2 = profiles.firstWhere((p) => p.id == 'p2');

      expect(p1.group, 'WebFleet');
      expect(p2.group, 'General');
      final groupNames = groups.map((g) => g.name).toSet();
      expect(groupNames.contains(p1.group), isTrue);
      expect(groupNames.contains(p2.group), isTrue);
    },
  );

  test('a version-5 file is still refused as too new', () async {
    final file = jsonEncode({
      'format': kBackupFormat,
      'version': 5,
      'profiles': [profileFixture().toJson()],
    });

    await expectLater(
      service.inspect(file),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.unsupportedVersion,
        ),
      ),
    );

    await expectLater(
      service.importFromJson(file, const ImportOptions()),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.unsupportedVersion,
        ),
      ),
    );
  });

  test('inspects a backup and lists its groups', () async {
    final groupStorage = GroupStorage();
    await groupStorage.saveGroups([
      const ProfileGroup(name: 'General'),
      const ProfileGroup(name: 'Existing', colorHex: '123456'),
    ]);

    final preview = await service.inspect(
      jsonEncode({
        'format': kBackupFormat,
        'version': kBackupVersion,
        'groups': [
          const ProfileGroup(name: 'Existing', colorHex: '654321').toJson(),
          const ProfileGroup(name: 'NewGroup', colorHex: 'ABCDEF').toJson(),
        ],
      }),
    );

    expect(preview.groupCount, 2);
    expect(preview.groups[0].id, 'Existing');
    expect(preview.groups[0].label, 'Existing');
    expect(preview.groups[0].detail, '654321');
    expect(preview.groups[0].exists, isTrue);

    expect(preview.groups[1].id, 'NewGroup');
    expect(preview.groups[1].label, 'NewGroup');
    expect(preview.groups[1].detail, 'ABCDEF');
    expect(preview.groups[1].exists, isFalse);
  });
}

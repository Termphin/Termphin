import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/screens/keys/key_form_screen.dart';
import 'package:termphin/screens/keys/key_manager_screen.dart';
import 'package:termphin/screens/search/global_search_launcher.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/widgets/ui/app_dropdown.dart';
import 'package:termphin/widgets/ui/empty_state.dart';
import 'package:termphin/widgets/ui/group_filter_chips.dart';
import 'package:termphin/widgets/ui/group_picker_field.dart';
import 'package:termphin/widgets/ui/list_section_header.dart';
import 'package:termphin/widgets/ui/selection_action_bar.dart';
import 'package:termphin/widgets/ui/tag_chip.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/platform_mocks.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ClipboardMock clipboard;
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
    clipboard = ClipboardMock()..install();
  });

  tearDown(() => clipboard.uninstall());

  Future<
    (ProviderContainer, FakeSshKeyStorage, FakeGroupStorage, FakeProfileStorage)
  >
  pumpManager(
    WidgetTester tester, {
    List<ProfileGroup> groups = const [
      ProfileGroup(name: 'General'),
      ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
    ],
    List<SshKey> keys = const [],
    List<SshProfile> profiles = const [],
  }) async {
    final fakeKeys = FakeSshKeyStorage(keys);
    final fakeProfiles = FakeProfileStorage(profiles);
    final fakeGroups = FakeGroupStorage(
      initialGroups: groups,
      profilesStorage: fakeProfiles,
      keysStorage: fakeKeys,
    );
    final container = ProviderContainer.test(
      overrides: [
        sshKeyStorageProvider.overrideWithValue(fakeKeys),
        profileStorageProvider.overrideWithValue(fakeProfiles),
        groupStorageProvider.overrideWithValue(fakeGroups),
      ],
    );

    await container.read(profileGroupsProvider.notifier).loadGroups();
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(tester, const KeyManagerScreen(), container: container);
    await tester.pumpAndSettle();

    return (container, fakeKeys, fakeGroups, fakeProfiles);
  }

  testWidgets('shows an empty state when no keys are stored', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpTestApp(tester, const KeyManagerScreen());
    await tester.pumpAndSettle();

    expect(find.text(t.keys.emptyTitle), findsOneWidget);
  });

  testWidgets('copies a public key using the visible copy action', (
    tester,
  ) async {
    final key = sshKeyFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_keys_v1': [key.encode()],
    });

    await pumpTestApp(tester, const KeyManagerScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.keys.copyPublicKey));
    await tester.pump();

    expect(clipboard.text, key.publicKeyOpenSSH);
  });

  testWidgets('also exposes copy public key in the overflow menu', (
    tester,
  ) async {
    final key = sshKeyFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_keys_v1': [key.encode()],
    });

    await pumpTestApp(tester, const KeyManagerScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppActionDropdown<String>));
    await tester.pumpAndSettle();

    expect(find.text(t.keys.copyPublicKey), findsWidgets);
    await tester.tap(find.text(t.keys.copyPublicKey).last);
    await tester.pumpAndSettle();

    expect(clipboard.text, key.publicKeyOpenSSH);
  });

  testWidgets(
    'the key manager renders one section per group with the right counts',
    (tester) async {
      final k1 = sshKeyFixture(
        id: 'k-1',
        name: 'General Key 1',
        group: 'General',
      );
      final k2 = sshKeyFixture(
        id: 'k-2',
        name: 'General Key 2',
        group: 'General',
      );
      final k3 = sshKeyFixture(
        id: 'k-3',
        name: 'Infra Key 1',
        group: 'Infrastructure',
      );

      await pumpManager(
        tester,
        groups: const [
          ProfileGroup(name: 'General'),
          ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
          ProfileGroup(name: 'EmptyGroup', colorHex: '52C41A'),
        ],
        keys: [k1, k2, k3],
      );

      expect(
        find.descendant(
          of: find.byType(ListSectionHeader),
          matching: find.text('General'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ListSectionHeader),
          matching: find.text('Infrastructure'),
        ),
        findsOneWidget,
      );
      expect(find.text('EmptyGroup'), findsNothing);

      final countBadges = find.byType(CountBadge);
      expect(countBadges, findsNWidgets(2));
      expect(tester.widget<CountBadge>(countBadges.at(0)).count, 2);
      expect(tester.widget<CountBadge>(countBadges.at(1)).count, 1);
      expect(find.byType(EmptyStateHint), findsNothing);

      expect(find.text('General Key 1'), findsOneWidget);
      expect(find.text('General Key 2'), findsOneWidget);
      expect(find.text('Infra Key 1'), findsOneWidget);
    },
  );

  testWidgets('a key in an unknown group is listed under General', (
    tester,
  ) async {
    final orphanKey = sshKeyFixture(
      id: 'k-orphan',
      name: 'Orphan Key',
      group: 'UnknownDeletedGroup',
    );
    final infraKey = sshKeyFixture(
      id: 'k-infra',
      name: 'Infra Key',
      group: 'Infrastructure',
    );

    await pumpManager(
      tester,
      groups: const [
        ProfileGroup(name: 'General'),
        ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
      ],
      keys: [orphanKey, infraKey],
    );

    expect(find.text('Orphan Key'), findsOneWidget);

    final countBadges = find.byType(CountBadge);
    expect(countBadges, findsNWidgets(2));
    expect(tester.widget<CountBadge>(countBadges.at(0)).count, 1);
    expect(tester.widget<CountBadge>(countBadges.at(1)).count, 1);
  });

  testWidgets(
    'pressing + on a group header opens KeyFormScreen with that group preselected',
    (tester) async {
      final k1 = sshKeyFixture(id: 'k-1', name: 'Key 1', group: 'General');
      final k2 = sshKeyFixture(
        id: 'k-2',
        name: 'Key 2',
        group: 'Infrastructure',
      );

      await pumpManager(
        tester,
        groups: const [
          ProfileGroup(name: 'General'),
          ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
        ],
        keys: [k1, k2],
      );

      final addButtons = find.byIcon(PhosphorIconsRegular.plus);
      expect(addButtons, findsWidgets);

      await tester.tap(addButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.byType(KeyFormScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GroupPickerField),
          matching: find.text('Infrastructure'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('overflow edit entry opens KeyFormScreen for existing key', (
    tester,
  ) async {
    final key = sshKeyFixture(name: 'My Server Key');

    await pumpManager(tester, keys: [key]);

    await tester.tap(find.byType(AppActionDropdown<String>));
    await tester.pumpAndSettle();

    expect(find.text(t.common.edit), findsOneWidget);
    await tester.tap(find.text(t.common.edit));
    await tester.pumpAndSettle();

    expect(find.byType(KeyFormScreen), findsOneWidget);
    expect(find.text(t.keys.editKeyTitle), findsOneWidget);
    expect(find.text('My Server Key'), findsOneWidget);
  });

  testWidgets(
    'the search box opens the search over everything, which finds the key',
    (tester) async {
      final k1 = sshKeyFixture(id: 'k-1', name: 'Alpha Key', group: 'General');
      final k2 = sshKeyFixture(id: 'k-2', name: 'Beta Key', group: 'General');

      await pumpManager(tester, keys: [k1, k2]);

      await tester.tap(find.byType(GlobalSearchLauncher));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('globalSearchField')),
        'alpha',
      );
      await tester.pumpAndSettle();

      final results = find.byType(GlobalSearchScreen);
      expect(
        find.descendant(of: results, matching: find.text('Alpha Key')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: results, matching: find.text('Beta Key')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'deleting a key no machine uses shows the plain dialog (no inUseTitle)',
    (tester) async {
      final key = sshKeyFixture(id: 'k-1', name: 'Unused Key');
      final otherMachine = profileFixture(
        id: 'p-1',
        name: 'Other Machine',
        sshKeyId: 'different-key-id',
      );

      await pumpManager(tester, keys: [key], profiles: [otherMachine]);

      await tester.tap(find.byType(AppActionDropdown<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.common.delete));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(t.keys.deleteTitle), findsOneWidget);
      expect(find.text(t.keys.inUseTitle), findsNothing);
      expect(
        find.text(t.keys.deleteConfirm(name: 'Unused Key')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.common.delete),
        ),
        findsOneWidget,
      );
      expect(find.text(t.keys.deleteAnyway), findsNothing);
    },
  );

  testWidgets(
    'deleting a key a machine uses shows inUseTitle and that machine\'s name',
    (tester) async {
      final key = sshKeyFixture(id: 'k-1', name: 'Shared Key');
      final machine = profileFixture(
        id: 'p-1',
        name: 'Production Server',
        sshKeyId: 'k-1',
      );

      await pumpManager(tester, keys: [key], profiles: [machine]);

      await tester.tap(find.byType(AppActionDropdown<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.common.delete));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(t.keys.inUseTitle), findsOneWidget);
      expect(find.text(t.keys.deleteTitle), findsNothing);
      expect(find.textContaining('Production Server'), findsOneWidget);
      expect(
        find.textContaining(t.keys.deleteConfirm(name: 'Shared Key')),
        findsOneWidget,
      );
      expect(find.text(t.keys.deleteAnyway), findsOneWidget);
    },
  );

  testWidgets('confirming that warning still deletes the key from storage', (
    tester,
  ) async {
    final key = sshKeyFixture(id: 'k-1', name: 'Shared Key');
    final machine = profileFixture(
      id: 'p-1',
      name: 'Production Server',
      sshKeyId: 'k-1',
    );

    final (_, fakeKeys, _, _) = await pumpManager(
      tester,
      keys: [key],
      profiles: [machine],
    );

    await tester.tap(find.byType(AppActionDropdown<String>));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.common.delete));
    await tester.pumpAndSettle();

    expect(find.text(t.keys.deleteAnyway), findsOneWidget);
    await tester.tap(find.text(t.keys.deleteAnyway));
    await tester.pumpAndSettle();

    expect(fakeKeys.deleteCount, 1);
    expect(fakeKeys.keys.any((k) => k.id == 'k-1'), isFalse);
    expect(find.text('Shared Key'), findsNothing);
  });

  testWidgets('the filter strip narrows the list to one group', (tester) async {
    final k1 = sshKeyFixture(id: 'k-1', name: 'General Key', group: 'General');
    final k2 = sshKeyFixture(
      id: 'k-2',
      name: 'Infra Key',
      group: 'Infrastructure',
    );

    await pumpManager(
      tester,
      groups: const [
        ProfileGroup(name: 'General'),
        ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
      ],
      keys: [k1, k2],
    );

    expect(find.text('General Key'), findsOneWidget);
    expect(find.text('Infra Key'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(GroupFilterChips),
        matching: find.text('Infrastructure'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Infra Key'), findsOneWidget);
    expect(find.text('General Key'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ListSectionHeader),
        matching: find.text('General'),
      ),
      findsNothing,
    );
  });

  testWidgets('the strip is absent when every key is in one group', (
    tester,
  ) async {
    final k1 = sshKeyFixture(id: 'k-1', name: 'Key 1', group: 'General');
    final k2 = sshKeyFixture(id: 'k-2', name: 'Key 2', group: 'General');

    await pumpManager(
      tester,
      groups: const [
        ProfileGroup(name: 'General'),
        ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
      ],
      keys: [k1, k2],
    );

    expect(find.byType(TagChip), findsNothing);
    expect(find.text(t.groups.allGroups), findsNothing);
  });

  testWidgets(
    'long-press enters selection mode and the bar reports "1 selected"',
    (tester) async {
      final k1 = sshKeyFixture(id: 'k-1', name: 'Key 1', group: 'General');
      final k2 = sshKeyFixture(id: 'k-2', name: 'Key 2', group: 'General');

      await pumpManager(tester, keys: [k1, k2]);

      expect(find.byType(SelectionActionBar), findsNothing);

      await tester.longPress(find.text('Key 1'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsOneWidget);
      expect(
        find.text(t.selection.countSelected(n: 1, count: 1)),
        findsOneWidget,
      );
    },
  );

  testWidgets('move to group writes the new group onto the selected keys', (
    tester,
  ) async {
    final k1 = sshKeyFixture(id: 'k-1', name: 'Key 1', group: 'General');
    final k2 = sshKeyFixture(id: 'k-2', name: 'Key 2', group: 'General');

    final (_, fakeKeys, _, _) = await pumpManager(
      tester,
      groups: const [
        ProfileGroup(name: 'General'),
        ProfileGroup(name: 'Infrastructure', colorHex: '4DA3FF'),
      ],
      keys: [k1, k2],
    );

    await tester.longPress(find.text('Key 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.selection.moveToGroup));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Infrastructure'));
    await tester.pumpAndSettle();

    expect(fakeKeys.updateCount, 1);
    expect(
      fakeKeys.keys.firstWhere((k) => k.id == 'k-1').group,
      'Infrastructure',
    );
    expect(find.byType(SelectionActionBar), findsNothing);
    expect(
      find.text(t.selection.moved(n: 1, count: 1, group: 'Infrastructure')),
      findsOneWidget,
    );
  });

  testWidgets(
    'deleting a selection containing a key a machine uses names that machine',
    (tester) async {
      final key = sshKeyFixture(id: 'k-1', name: 'Shared Key');
      final machine = profileFixture(
        id: 'p-1',
        name: 'Production Server',
        sshKeyId: 'k-1',
      );

      final (_, fakeKeys, _, _) = await pumpManager(
        tester,
        keys: [key],
        profiles: [machine],
      );

      await tester.longPress(find.text('Shared Key'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SelectionActionBar),
          matching: find.byIcon(PhosphorIconsRegular.trash),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(t.selection.inUseTitle), findsOneWidget);
      expect(find.textContaining('Production Server'), findsOneWidget);
      expect(find.text(t.selection.deleteAnyway), findsOneWidget);

      await tester.tap(find.text(t.selection.deleteAnyway));
      await tester.pumpAndSettle();

      expect(fakeKeys.deleteCount, 1);
      expect(fakeKeys.keys.any((k) => k.id == 'k-1'), isFalse);
      expect(find.byType(SelectionActionBar), findsNothing);
      expect(find.text(t.selection.deleted(n: 1, count: 1)), findsOneWidget);
    },
  );

  testWidgets(
    'deleting a selection when no machines use the keys shows plain delete dialog',
    (tester) async {
      final key = sshKeyFixture(id: 'k-1', name: 'Unused Key');

      final (_, fakeKeys, _, _) = await pumpManager(tester, keys: [key]);

      await tester.longPress(find.text('Unused Key'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SelectionActionBar),
          matching: find.byIcon(PhosphorIconsRegular.trash),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(t.selection.deleteTitle(n: 1, count: 1)),
        findsOneWidget,
      );
      expect(find.text(t.selection.deleteConfirm), findsOneWidget);
      expect(find.text(t.selection.inUseTitle), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.common.delete),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeKeys.deleteCount, 1);
      expect(fakeKeys.keys.any((k) => k.id == 'k-1'), isFalse);
      expect(find.byType(SelectionActionBar), findsNothing);
      expect(find.text(t.selection.deleted(n: 1, count: 1)), findsOneWidget);
    },
  );

  testWidgets(
    'tapping toggles selection and leaving zero selected exits mode',
    (tester) async {
      final k1 = sshKeyFixture(id: 'k-1', name: 'Key 1', group: 'General');
      final k2 = sshKeyFixture(id: 'k-2', name: 'Key 2', group: 'General');

      await pumpManager(tester, keys: [k1, k2]);

      await tester.longPress(find.text('Key 1'));
      await tester.pumpAndSettle();
      expect(
        find.text(t.selection.countSelected(n: 1, count: 1)),
        findsOneWidget,
      );

      await tester.tap(find.text('Key 2'));
      await tester.pumpAndSettle();
      expect(
        find.text(t.selection.countSelected(n: 2, count: 2)),
        findsOneWidget,
      );

      await tester.tap(find.text('Key 2'));
      await tester.pumpAndSettle();
      expect(
        find.text(t.selection.countSelected(n: 1, count: 1)),
        findsOneWidget,
      );

      await tester.tap(find.text('Key 1'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionActionBar), findsNothing);
    },
  );

  testWidgets('clearing selection exits selection mode', (tester) async {
    final k1 = sshKeyFixture(id: 'k-1', name: 'Key 1', group: 'General');
    await pumpManager(tester, keys: [k1]);

    await tester.longPress(find.text('Key 1'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionActionBar), findsOneWidget);

    await tester.tap(find.byTooltip(t.selection.clear));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionActionBar), findsNothing);
  });
}

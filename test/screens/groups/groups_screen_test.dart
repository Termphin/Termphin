import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/snippets_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/screens/groups/group_form_screen.dart';
import 'package:termphin/screens/groups/groups_screen.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/services/storage/snippet_storage.dart';
import 'package:termphin/widgets/ui/group_dot.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A real `SshKeyStorage` seals through `SecretCipher.instance`, which
  /// never completes in a plain widget test, so [keys] are handed to the
  /// screen through a fake instead.
  Future<ProviderContainer> pumpGroupsScreen(
    WidgetTester tester, {
    List<SshProfile> profiles = const [],
    List<String> groups = const [GroupStorage.defaultGroup],
    List<ProfileGroup>? profileGroups,
    List<SshKey> keys = const [],
    List<Snippet> snippets = const [],
  }) async {
    final fakeProfiles = FakeProfileStorage(profiles);
    final initialGroups =
        profileGroups ?? [for (final g in groups) ProfileGroup(name: g)];
    final fakeGroups = FakeGroupStorage(
      initialGroups: initialGroups,
      profilesStorage: fakeProfiles,
    );
    final fakeKeys = FakeSshKeyStorage(keys);
    if (snippets.isNotEmpty) {
      await SnippetStorage().saveSnippets(snippets);
    }
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(fakeProfiles),
        groupStorageProvider.overrideWithValue(fakeGroups),
        sshKeyStorageProvider.overrideWithValue(fakeKeys),
      ],
    );

    await container.read(profilesProvider.notifier).loadProfiles();
    await container.read(snippetsProvider.notifier).loadSnippets();
    await container.read(profileGroupsProvider.notifier).loadGroups();

    await pumpTestApp(tester, const GroupsScreen(), container: container);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('displays groups with Default badge for General', (tester) async {
    final p1 = profileFixture(id: 'p1', group: 'General');
    final p2 = profileFixture(id: 'p2', group: 'Staging');

    await pumpGroupsScreen(
      tester,
      profiles: [p1, p2],
      groups: ['General', 'Staging'],
    );

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
  });

  testWidgets('lists General when it is the only group', (tester) async {
    await pumpGroupsScreen(tester, groups: ['General']);

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('can add a new group through the form', (tester) async {
    final container = await pumpGroupsScreen(tester, groups: ['General']);

    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('groupNameField')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('groupNameField')),
      'Production',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsOneWidget);
    expect(
      container.read(profileGroupsProvider).map((g) => g.name),
      contains('Production'),
    );
  });

  testWidgets('prevents creating duplicate groups', (tester) async {
    final container = await pumpGroupsScreen(
      tester,
      groups: ['General', 'Existing'],
    );

    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('groupNameField')),
      'Existing',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('A group with this name already exists.'), findsOneWidget);
    expect(container.read(profileGroupsProvider).length, 2);
  });

  testWidgets(
    'a group row shows its colour dot and a count spanning profiles, keys and snippets',
    (tester) async {
      final p1 = profileFixture(id: 'p1', group: 'Dev');
      final p2 = profileFixture(id: 'p2', group: 'Dev');
      final k1 = sshKeyFixture(id: 'k1', group: 'Dev');
      final s1 = snippetFixture(id: 's1', group: 'Dev');
      final s2 = snippetFixture(id: 's2', group: 'Dev');
      final s3 = snippetFixture(id: 's3', group: 'Dev');

      await pumpGroupsScreen(
        tester,
        profileGroups: [
          const ProfileGroup(name: 'General'),
          const ProfileGroup(name: 'Dev', colorHex: '4DA3FF'),
        ],
        profiles: [p1, p2],
        keys: [k1],
        snippets: [s1, s2, s3],
      );

      expect(
        find.text('2 machines \u00b7 1 key \u00b7 3 snippets'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is GroupDot && w.colorHex == '4DA3FF'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping a row opens the group form with that group loaded', (
    tester,
  ) async {
    await pumpGroupsScreen(
      tester,
      profileGroups: [
        const ProfileGroup(name: 'General'),
        const ProfileGroup(name: 'Dev', colorHex: '4DA3FF'),
      ],
    );

    await tester.tap(find.text('Dev'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupFormScreen), findsOneWidget);
    expect(find.text('Edit group'), findsOneWidget);
    expect(find.text('Dev'), findsWidgets);
  });

  testWidgets('General has no delete button and its name cannot be edited', (
    tester,
  ) async {
    await pumpGroupsScreen(tester, groups: ['General', 'Custom']);

    expect(find.byTooltip('Delete'), findsOneWidget);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupFormScreen), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);
  });

  testWidgets('deleting a group reassigns its machines to General', (
    tester,
  ) async {
    final p1 = profileFixture(id: 'p1', name: 'Web 1', group: 'ToDrop');
    final container = await pumpGroupsScreen(
      tester,
      profiles: [p1],
      groups: ['General', 'ToDrop'],
    );

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete group?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('ToDrop'), findsNothing);
    expect(
      container.read(profileGroupsProvider).map((g) => g.name),
      isNot(contains('ToDrop')),
    );

    final profiles = container.read(profilesProvider);
    expect(profiles.firstWhere((p) => p.id == 'p1').group, 'General');
  });

  testWidgets('no row carries a drag handle - the whole row is the handle', (
    tester,
  ) async {
    await pumpGroupsScreen(tester, groups: ['General', 'Staging', 'Prod']);

    expect(find.byIcon(PhosphorIconsRegular.dotsSixVertical), findsNothing);
    expect(find.byType(ReorderableDelayedDragStartListener), findsNWidgets(3));
  });

  testWidgets('General is draggable like any other group', (tester) async {
    final container = await pumpGroupsScreen(
      tester,
      groups: ['General', 'Staging'],
    );

    final general = find.text('General');
    final rowHeight = tester.getSize(find.byType(GroupDot).first).height + 60;
    final gesture = await tester.startGesture(tester.getCenter(general));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
    for (var moved = 0.0; moved < rowHeight * 1.5; moved += 20) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(profileGroupsProvider).map((g) => g.name).toList(), [
      'Staging',
      'General',
    ]);
  });

  testWidgets('on a desktop a plain drag moves a group, no hold needed', (
    tester,
  ) async {
    final container = await pumpGroupsScreen(
      tester,
      groups: ['General', 'Staging'],
    );

    final general = find.text('General');
    final rowHeight = tester.getSize(find.byType(GroupDot).first).height + 60;
    final gesture = await tester.startGesture(
      tester.getCenter(general),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var moved = 0.0; moved < rowHeight * 1.5; moved += 20) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(profileGroupsProvider).map((g) => g.name).toList(), [
      'Staging',
      'General',
    ]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

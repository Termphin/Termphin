import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/screens/groups/group_form_screen.dart';
import 'package:termphin/screens/home_screen.dart';
import 'package:termphin/screens/search/global_search_launcher.dart';
import 'package:termphin/services/ssh/ssh_session_manager.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/widgets/groups/group_dot.dart';
import 'package:termphin/widgets/groups/group_filter_chips.dart';
import 'package:termphin/widgets/groups/group_section_header.dart';
import 'package:termphin/widgets/profiles/profile_card.dart';
import 'package:termphin/widgets/profiles/profile_form_dialog.dart';
import 'package:termphin/widgets/ui/app_badge.dart';
import 'package:termphin/widgets/ui/selection_action_bar.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = SshSessionManager.instance;
  final createdTabIds = <String>[];

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    for (final id in createdTabIds) {
      await manager.forgetTab(id);
    }
    createdTabIds.clear();
  });

  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    List<SshProfile> profiles, {
    List<ProfileGroup>? knownGroups,
  }) async {
    final fakeProfiles = FakeProfileStorage(profiles);
    final initialGroups =
        knownGroups ??
        [
          for (final g in <String>{
            GroupStorage.defaultGroup,
            for (final p in profiles) p.group,
          })
            ProfileGroup(name: g),
        ];
    final fakeGroups = FakeGroupStorage(
      initialGroups: initialGroups,
      profilesStorage: fakeProfiles,
    );
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(fakeProfiles),
        groupStorageProvider.overrideWithValue(fakeGroups),
        sshKeyStorageProvider.overrideWithValue(FakeSshKeyStorage()),
      ],
    );
    container.read(profilesProvider);
    await container.read(profilesProvider.notifier).loadProfiles();
    await container.read(profileGroupsProvider.notifier).loadGroups();
    await pumpTestApp(tester, const HomeScreen(), container: container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    return container;
  }

  testWidgets('typing user@host on an empty list opens a filled-in form', (
    tester,
  ) async {
    final t = AppLocale.en.buildSync();
    await pumpHome(tester, const []);

    await tester.enterText(find.byType(TextField), 'nonsense words');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(t.profiles.quickAddInvalid), findsOneWidget);
    expect(find.byType(ProfileFormDialog), findsNothing);

    await tester.enterText(find.byType(TextField), 'alice@devbox');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileFormDialog), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'devbox'),
      findsAtLeastNWidgets(1),
    );
    expect(find.widgetWithText(TextFormField, 'alice'), findsOneWidget);
  });

  testWidgets('an empty list says where a server comes from', (tester) async {
    final t = AppLocale.en.buildSync();
    await pumpHome(tester, const []);

    expect(find.text(t.profiles.addFirstMachine), findsOneWidget);
    await tester.tap(find.text(t.profiles.noServerYet));
    await tester.pumpAndSettle();

    expect(find.text(t.serverGuide.title), findsOneWidget);
    expect(find.text(t.serverGuide.computerTitle), findsOneWidget);
    expect(find.text(t.serverGuide.cloudTitle), findsOneWidget);
  });

  testWidgets(
    'profile card opens the live tab with sibling scope none when one is connected',
    (tester) async {
      final profile = profileFixture();
      final liveId = manager.adoptRemoteSession(profile, 'devbox-live');
      manager.getSession(liveId)!.dropped = false;
      final droppedId = manager.adoptRemoteSession(profile, 'devbox-dropped');
      createdTabIds.addAll([liveId, droppedId]);

      final container = await pumpHome(tester, [profile]);

      await tester.tap(find.byType(ProfileCard));
      await tester.pump();

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay, isNotNull);
      expect(overlay!.$1, liveId);
      expect(overlay.$2, profile);
      expect(overlay.$3, SiblingScope.none);
    },
  );

  testWidgets(
    'profile card resumes the dropped tab with sibling scope none when nothing is connected',
    (tester) async {
      final profile = profileFixture();
      final droppedId = manager.adoptRemoteSession(profile, 'devbox-dropped');
      createdTabIds.add(droppedId);

      final container = await pumpHome(tester, [profile]);

      await tester.tap(find.byType(ProfileCard));
      await tester.pump();

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay, isNotNull);
      expect(overlay!.$1, droppedId);
      expect(overlay.$2, profile);
      expect(overlay.$3, SiblingScope.none);
    },
  );

  testWidgets(
    'a dropped agent tab reads Detached, a dropped plain-SSH tab reads Disconnected',
    (tester) async {
      final profile = profileFixture();
      final agentId = manager.adoptRemoteSession(profile, 'devbox-agent');
      final plainId = manager.adoptRemoteSession(
        profile,
        'devbox-plain',
        multiplexer: Multiplexer.none,
      );
      createdTabIds.addAll([agentId, plainId]);

      await pumpHome(tester, [profile]);

      expect(find.text('Detached'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
    },
  );

  testWidgets(
    'a session still handshaking reads Connecting rather than an uptime',
    (tester) async {
      final profile = profileFixture();
      final connectingId = manager.adoptRemoteSession(profile, 'devbox-new');
      manager.getSession(connectingId)!
        ..dropped = false
        ..connecting = true;
      createdTabIds.add(connectingId);

      await pumpHome(tester, [profile]);

      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.text('0m'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'profile card starts a brand new session with sibling scope none when there is no tab at all',
    (tester) async {
      final profile = profileFixture();

      final container = await pumpHome(tester, [profile]);

      await tester.tap(find.byType(ProfileCard));
      await tester.pump();

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay, isNotNull);
      expect(_uuidPattern.hasMatch(overlay!.$1), isTrue);
      expect(overlay.$2, profile);
      expect(overlay.$3, SiblingScope.none);
    },
  );

  testWidgets(
    'a session row always opens its own tab with sibling scope none, ignoring which one is live',
    (tester) async {
      final profile = profileFixture();
      final liveId = manager.adoptRemoteSession(profile, 'devbox-live');
      manager.getSession(liveId)!.dropped = false;
      final droppedId = manager.adoptRemoteSession(profile, 'devbox-dropped');
      createdTabIds.addAll([liveId, droppedId]);

      final container = await pumpHome(tester, [profile]);

      await tester.tap(find.text('devbox-dropped'));
      await tester.pump();

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay, isNotNull);
      expect(overlay!.$1, droppedId);
      expect(overlay.$2, profile);
      expect(overlay.$3, SiblingScope.none);
    },
  );

  testWidgets(
    'the new session row always starts a fresh session with sibling scope none',
    (tester) async {
      final profile = profileFixture();
      final liveId = manager.adoptRemoteSession(profile, 'devbox-live');
      manager.getSession(liveId)!.dropped = false;
      createdTabIds.add(liveId);

      final container = await pumpHome(tester, [profile]);

      await tester.tap(find.text('New session'));
      await tester.pump();

      final overlay = container.read(terminalOverlayProvider);
      expect(overlay, isNotNull);
      expect(_uuidPattern.hasMatch(overlay!.$1), isTrue);
      expect(overlay.$1, isNot(liveId));
      expect(overlay.$2, profile);
      expect(overlay.$3, SiblingScope.none);
    },
  );

  testWidgets('the group filter strip narrows the list to one group', (
    tester,
  ) async {
    final p1 = profileFixture(id: 'p1', name: 'Server A', group: 'General');
    final p2 = profileFixture(id: 'p2', name: 'Server B', group: 'Production');

    await pumpHome(tester, [p1, p2]);

    await tester.tap(
      find.descendant(
        of: find.byType(GroupFilterChips),
        matching: find.text('Production'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Server B'), findsOneWidget);
    expect(find.text('Server A'), findsNothing);
    expect(find.byType(GroupSectionHeader), findsOneWidget);
  });

  testWidgets('the filter strip stays hidden while there is one group', (
    tester,
  ) async {
    await pumpHome(tester, [profileFixture(id: 'p1', name: 'Server A')]);

    final t = AppLocale.en.buildSync();
    expect(find.text(t.groups.allGroups), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets(
    'renders machines grouped by group with count badge and action buttons',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A', group: 'General');
      final p2 = profileFixture(
        id: 'p2',
        name: 'Server B',
        group: 'Production',
      );

      final t = AppLocale.en.buildSync();
      await pumpHome(tester, [p1, p2]);

      expect(find.byType(GroupSectionHeader), findsNWidgets(2));
      final headers = tester
          .widgetList<GroupSectionHeader>(find.byType(GroupSectionHeader))
          .toList();
      expect(headers[0].group.name, 'General');
      expect(headers[0].count, 1);
      expect(headers[1].group.name, 'Production');
      expect(headers[1].count, 1);
      expect(find.byType(GroupDot), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byType(GroupSectionHeader),
          matching: find.text(t.groups.general),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(GroupSectionHeader),
          matching: find.text('Production'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AppBadge), findsNWidgets(2));
      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('Server B'), findsOneWidget);
    },
  );

  testWidgets(
    'every group header loads the sessions of the machines it counts',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A', group: 'General');
      final p2 = profileFixture(
        id: 'p2',
        name: 'Server B',
        group: 'Production',
      );
      final p3 = profileFixture(
        id: 'p3',
        name: 'Server C',
        group: 'Production',
      );

      await pumpHome(tester, [p1, p2, p3]);

      final headers = tester
          .widgetList<GroupSectionHeader>(find.byType(GroupSectionHeader))
          .toList();
      expect(headers.length, 2);
      for (final header in headers) {
        expect(header.onLoadSessions, isNotNull);
        expect(header.isLoadingSessions, isFalse);
      }
      expect(
        find.byKey(const ValueKey('groupLoadSessionsButton')),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'the sort button sits beside the search box, as tall as it, and sorts',
    (tester) async {
      final t = AppLocale.en.buildSync();
      final a = profileFixture(id: 'a', name: 'Alpha', group: 'Production');
      final b = profileFixture(id: 'b', name: 'Bravo', group: 'Production');
      final c = profileFixture(id: 'c', name: 'Charlie', group: 'General');

      await pumpHome(tester, [a, b, c]);

      final chip = find.byKey(const ValueKey('profileSortButton'));
      final search = tester.getRect(find.byType(GlobalSearchLauncher));
      expect(tester.getRect(chip).top, search.top);
      expect(tester.getRect(chip).height, search.height);
      expect(tester.getRect(chip).left, greaterThan(search.right));

      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.profiles.sortZA).last);
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Bravo')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );
    },
  );

  testWidgets('the sort button stays when there is one group and no strip', (
    tester,
  ) async {
    await pumpHome(tester, [profileFixture(group: 'General')]);

    expect(find.byKey(const ValueKey('profileSortButton')), findsOneWidget);
  });

  testWidgets('the pencil on a group header edits that group', (tester) async {
    final profile = profileFixture(group: 'Production');
    final t = AppLocale.en.buildSync();

    await pumpHome(tester, [profile]);

    await tester.tap(find.byTooltip(t.groups.editGroup).last);
    await tester.pumpAndSettle();

    expect(find.byType(GroupFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, t.groups.editGroup), findsOneWidget);
    expect(find.text('Production'), findsWidgets);
  });

  testWidgets(
    'plus button on group header opens ProfileFormDialog with initial group',
    (tester) async {
      final profile = profileFixture(group: 'Staging');

      await pumpHome(tester, [profile]);

      expect(find.byTooltip('Add machine'), findsWidgets);
      await tester.tap(find.byTooltip('Add machine').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileFormDialog), findsOneWidget);
      expect(find.text('Staging'), findsWidgets);
    },
  );

  testWidgets(
    'home renders a dot and its own edit pencil on every section header',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A', group: 'General');
      final p2 = profileFixture(
        id: 'p2',
        name: 'Server B',
        group: 'Production',
      );
      final t = AppLocale.en.buildSync();

      await pumpHome(tester, [p1, p2]);

      expect(find.byType(GroupSectionHeader), findsNWidgets(2));
      expect(find.byType(GroupDot), findsNWidgets(4));
      expect(find.byTooltip(t.groups.editGroup), findsNWidgets(2));
    },
  );

  testWidgets(
    'a profile in an unknown group appears under General rather than in a section of its own',
    (tester) async {
      final p1 = profileFixture(
        id: 'p1',
        name: 'Server In Deleted Group',
        group: 'OldDeletedGroup',
      );

      await pumpHome(
        tester,
        [p1],
        knownGroups: [const ProfileGroup(name: GroupStorage.defaultGroup)],
      );

      expect(find.text('OldDeletedGroup'), findsNothing);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Server In Deleted Group'), findsOneWidget);
    },
  );

  testWidgets(
    'long-press enters selection mode and the bar reports "1 selected"',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A');
      final p2 = profileFixture(id: 'p2', name: 'Server B');

      await pumpHome(tester, [p1, p2]);

      expect(find.byType(SelectionActionBar), findsNothing);

      await tester.longPress(find.text('Server A'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      final cards = tester
          .widgetList<ProfileCard>(find.byType(ProfileCard))
          .toList();
      expect(cards.firstWhere((c) => c.profile.id == 'p1').selected, isTrue);
      expect(cards.firstWhere((c) => c.profile.id == 'p2').selected, isFalse);
    },
  );

  testWidgets('tapping a second card makes it 2, tapping it again makes it 1', (
    tester,
  ) async {
    final p1 = profileFixture(id: 'p1', name: 'Server A');
    final p2 = profileFixture(id: 'p2', name: 'Server B');

    await pumpHome(tester, [p1, p2]);

    await tester.longPress(find.text('Server A'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Server B'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Server B'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Server A'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionActionBar), findsNothing);
  });

  testWidgets(
    'move to group writes the new group onto both selected machines',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A', group: 'General');
      final p2 = profileFixture(id: 'p2', name: 'Server B', group: 'General');

      final container = await pumpHome(
        tester,
        [p1, p2],
        knownGroups: [
          const ProfileGroup(name: 'General'),
          const ProfileGroup(name: 'Production'),
        ],
      );

      await tester.longPress(find.text('Server A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Server B'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);

      final t = AppLocale.en.buildSync();
      await tester.tap(find.byTooltip(t.selection.moveToGroup));
      await tester.pumpAndSettle();

      expect(find.text('Production'), findsWidgets);
      await tester.tap(find.text('Production').last);
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsNothing);

      final updated = container.read(profilesProvider);
      expect(updated.firstWhere((p) => p.id == 'p1').group, 'Production');
      expect(updated.firstWhere((p) => p.id == 'p2').group, 'Production');
    },
  );

  testWidgets(
    'deleting a selection that nothing points at asks once and removes them',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A');
      final p2 = profileFixture(id: 'p2', name: 'Server B');

      final container = await pumpHome(tester, [p1, p2]);

      await tester.longPress(find.text('Server A'));
      await tester.pumpAndSettle();

      final t = AppLocale.en.buildSync();
      await tester.tap(
        find.descendant(
          of: find.byType(SelectionActionBar),
          matching: find.byTooltip(t.common.delete),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Delete 1 item?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.common.delete),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsNothing);
      final profiles = container.read(profilesProvider);
      expect(profiles.map((p) => p.id), isNot(contains('p1')));
      expect(find.text('Server A'), findsNothing);
      expect(find.text('Server B'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting a machine that is another\'s jump host names that other machine in the dialog',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Bastion Host');
      final p2 = profileFixture(
        id: 'p2',
        name: 'Target Behind Bastion',
        jumpHostProfileId: 'p1',
      );

      final container = await pumpHome(tester, [p1, p2]);

      await tester.longPress(find.text('Bastion Host'));
      await tester.pumpAndSettle();

      final t = AppLocale.en.buildSync();
      await tester.tap(
        find.descendant(
          of: find.byType(SelectionActionBar),
          matching: find.byTooltip(t.common.delete),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.selection.inUseTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Target Behind Bastion'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.selection.deleteAnyway),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.selection.deleteAnyway),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsNothing);
      final profiles = container.read(profilesProvider);
      expect(profiles.map((p) => p.id), isNot(contains('p1')));
      expect(find.text('Bastion Host'), findsNothing);
      expect(find.text('Target Behind Bastion'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping clear button on SelectionActionBar leaves selection mode',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A');
      final p2 = profileFixture(id: 'p2', name: 'Server B');

      await pumpHome(tester, [p1, p2]);

      await tester.longPress(find.text('Server A'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsOneWidget);

      final t = AppLocale.en.buildSync();
      await tester.tap(find.byTooltip(t.selection.clear));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsNothing);
    },
  );

  testWidgets(
    'search and group filter strip stay visible and keep working in selection mode',
    (tester) async {
      final p1 = profileFixture(id: 'p1', name: 'Server A', group: 'General');
      final p2 = profileFixture(
        id: 'p2',
        name: 'Server B',
        group: 'Production',
      );

      await pumpHome(tester, [p1, p2]);

      await tester.longPress(find.text('Server A'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      expect(find.byType(GlobalSearchLauncher), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(GroupFilterChips),
          matching: find.text('Production'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ProfileCard),
          matching: find.text('Server B'),
        ),
        findsOneWidget,
      );
      expect(find.text('Server A'), findsNothing);
      expect(find.byType(SelectionActionBar), findsOneWidget);
    },
  );
}

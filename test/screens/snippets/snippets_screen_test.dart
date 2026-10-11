import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/snippets_provider.dart';
import 'package:termphin/screens/main_shell.dart';
import 'package:termphin/screens/search/global_search_launcher.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/screens/snippets/snippets_screen.dart';
import 'package:termphin/services/storage/group_storage.dart';
import 'package:termphin/widgets/snippets/snippet_picker_panel.dart';
import 'package:termphin/widgets/ui/group_filter_chips.dart';
import 'package:termphin/widgets/ui/group_picker_field.dart';
import 'package:termphin/widgets/ui/list_section_header.dart';
import 'package:termphin/widgets/ui/selection_action_bar.dart';
import 'package:termphin/widgets/ui/tag_chip.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

/// Without `SharedPreferences.resetStatic()` the instance cached by the
/// previous test is handed back, so one test's saved snippet turns up in the
/// next one's empty list; the real `SnippetStorage` also writes through its
/// own static queue over those same preference statics, which strands a
/// later write and reads as a mutation quietly not happening unless that
/// queue is reset too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  Future<ProviderContainer> pumpSnippets(
    WidgetTester tester, {
    List<Snippet> snippets = const [],
    List<ProfileGroup>? groups,
  }) async {
    final groupList =
        groups ?? [const ProfileGroup(name: GroupStorage.defaultGroup)];
    final fakeGroups = FakeGroupStorage(initialGroups: groupList);
    SharedPreferences.setMockInitialValues({
      'snippets': Snippet.encodeList(snippets),
    });
    SharedPreferences.resetStatic();

    final container = ProviderContainer.test(
      overrides: [
        groupStorageProvider.overrideWithValue(fakeGroups),
        snippetStorageProvider.overrideWithValue(FakeSnippetStorage(snippets)),
      ],
    );
    await container.read(snippetsProvider.notifier).loadSnippets();
    await container.read(profileGroupsProvider.notifier).loadGroups();
    await pumpTestApp(tester, const SnippetsScreen(), container: container);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('opens snippets from the bottom navigation', (tester) async {
    await pumpTestApp(tester, const MainShell());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(PhosphorIconsRegular.codeBlock), findsWidgets);

    await tester.tap(find.text('Snippets').hitTestable());
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bottomNavBar')),
        matching: find.byIcon(PhosphorIconsFill.codeBlock),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnippetsScreen), findsOneWidget);
  });

  testWidgets('adds a snippet with readable editor fields', (tester) async {
    await pumpTestApp(tester, const SnippetsScreen());
    await tester.pumpAndSettle();

    expect(find.text('No snippets yet'), findsOneWidget);

    await tester.tap(find.byTooltip('New snippet'));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey('snippetNameField'));
    final commandField = find.byKey(const ValueKey('snippetCommandField'));
    final groupField = find.byType(GroupPickerField);
    expect(tester.getSize(nameField).height, greaterThanOrEqualTo(52));
    expect(tester.getSize(commandField).height, greaterThanOrEqualTo(150));
    expect(tester.getSize(groupField).height, greaterThanOrEqualTo(44));

    await tester.enterText(nameField, 'Restart nginx');
    await tester.enterText(commandField, 'sudo systemctl restart nginx');
    final saveButton = find.widgetWithText(TextButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Restart nginx'), findsOneWidget);
    expect(find.text('sudo systemctl restart nginx'), findsOneWidget);
  });

  testWidgets('tapping a snippet runs it rather than opening the editor', (
    tester,
  ) async {
    await _seedSnippet(tester);

    await tester.tap(find.text('Restart nginx'));
    await tester.pumpAndSettle();

    expect(find.text(t.snippets.runTitle), findsOneWidget);
    expect(find.text(t.snippets.editTitle), findsNothing);
  });

  testWidgets('deleting from the card asks before it does it', (tester) async {
    await _seedSnippet(tester);

    await tester.tap(find.byTooltip(t.snippets.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.delete).last);
    await tester.pumpAndSettle();

    expect(find.text(t.snippets.deleteTitle), findsOneWidget);
    expect(find.text('Restart nginx'), findsWidgets);

    await tester.tap(find.text(t.common.delete).last);
    await tester.pumpAndSettle();

    expect(find.text('Restart nginx'), findsNothing);
    expect(find.text(t.snippets.emptyTitle), findsOneWidget);
  });

  testWidgets(
    'snippets render under one section per group with correct counts',
    (tester) async {
      await pumpSnippets(
        tester,
        groups: [
          const ProfileGroup(name: 'General'),
          const ProfileGroup(name: 'DevOps'),
        ],
        snippets: [
          snippetFixture(id: 's1', name: 'General Snip 1', group: 'General'),
          snippetFixture(id: 's2', name: 'General Snip 2', group: 'General'),
          snippetFixture(id: 's3', name: 'DevOps Snip', group: 'DevOps'),
        ],
      );

      expect(find.text('General Snip 1'), findsOneWidget);
      expect(find.text('General Snip 2'), findsOneWidget);
      expect(find.text('DevOps Snip'), findsOneWidget);

      final headers = tester
          .widgetList<ListSectionHeader>(find.byType(ListSectionHeader))
          .toList();
      expect(headers.length, 2);
      expect(headers[0].count, 2);
      expect(headers[1].count, 1);
      expect(
        find.descendant(
          of: find.byWidget(headers[0]),
          matching: find.text('General'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byWidget(headers[1]),
          matching: find.text('DevOps'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('the group filter strip narrows the list to one group', (
    tester,
  ) async {
    await pumpSnippets(
      tester,
      groups: [
        const ProfileGroup(name: 'General'),
        const ProfileGroup(name: 'DevOps'),
      ],
      snippets: [
        snippetFixture(id: 's1', name: 'General Snip', group: 'General'),
        snippetFixture(id: 's2', name: 'DevOps Snip', group: 'DevOps'),
      ],
    );

    expect(find.byType(GroupFilterChips), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(GroupFilterChips),
        matching: find.text('DevOps'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DevOps Snip'), findsOneWidget);
    expect(find.text('General Snip'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(GroupFilterChips),
        matching: find.text('DevOps'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('General Snip'), findsOneWidget);
  });

  testWidgets('the filter strip stays hidden while there is one group', (
    tester,
  ) async {
    await pumpSnippets(
      tester,
      snippets: [snippetFixture(id: 's1', name: 'Only Snip')],
    );

    expect(find.byType(GroupFilterChips), findsNothing);
    expect(find.text(t.groups.allGroups), findsNothing);
  });

  testWidgets(
    'the + on a group header opens the form with that group preselected',
    (tester) async {
      await pumpSnippets(
        tester,
        groups: [
          const ProfileGroup(name: 'General'),
          const ProfileGroup(name: 'DevOps'),
        ],
        snippets: [
          snippetFixture(id: 's1', name: 'General Snip', group: 'General'),
          snippetFixture(id: 's2', name: 'DevOps Snip', group: 'DevOps'),
        ],
      );

      final devOpsHeader = find.ancestor(
        of: find.text('DevOps'),
        matching: find.byType(ListSectionHeader),
      );
      expect(devOpsHeader, findsOneWidget);

      final addButton = find.descendant(
        of: devOpsHeader,
        matching: find.byIcon(PhosphorIconsRegular.plus),
      );
      expect(addButton, findsOneWidget);

      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.byType(GroupPickerField), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GroupPickerField),
          matching: find.text('DevOps'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a snippet in an unknown group appears under General', (
    tester,
  ) async {
    await pumpSnippets(
      tester,
      groups: [const ProfileGroup(name: 'General')],
      snippets: [
        snippetFixture(
          id: 's1',
          name: 'Lost Snippet',
          group: 'NonExistentGroup',
        ),
      ],
    );

    expect(find.text('Lost Snippet'), findsOneWidget);
    expect(find.text('NonExistentGroup'), findsNothing);

    final headers = tester
        .widgetList<ListSectionHeader>(find.byType(ListSectionHeader))
        .toList();
    expect(headers.length, 1);
    expect(headers[0].count, 1);
    expect(
      find.descendant(
        of: find.byWidget(headers[0]),
        matching: find.text('General'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the search box opens the search over everything, which finds a snippet by its command',
    (tester) async {
      await pumpSnippets(
        tester,
        groups: [const ProfileGroup(name: 'General')],
        snippets: [
          snippetFixture(
            id: 's1',
            name: 'Deploy app',
            command: 'git pull && make deploy',
          ),
          snippetFixture(id: 's2', name: 'Check logs', command: 'journalctl'),
        ],
      );

      await tester.tap(find.byType(GlobalSearchLauncher));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('globalSearchField')),
        'make',
      );
      await tester.pumpAndSettle();

      final results = find.byType(GlobalSearchScreen);
      expect(
        find.descendant(of: results, matching: find.text('Deploy app')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: results, matching: find.text('Check logs')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the chip row in the picker panel is absent when only one group exists',
    (tester) async {
      final container = ProviderContainer.test(
        overrides: [
          groupStorageProvider.overrideWithValue(
            FakeGroupStorage(
              initialGroups: [const ProfileGroup(name: 'General')],
            ),
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'snippets': Snippet.encodeList([
          snippetFixture(
            id: 's1',
            name: 'Single group snippet',
            group: 'General',
          ),
        ]),
      });
      SharedPreferences.resetStatic();
      await container.read(snippetsProvider.notifier).loadSnippets();
      await container.read(profileGroupsProvider.notifier).loadGroups();

      await pumpTestApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showSnippetSpotlight(context, onSelect: (_, _) {}),
              child: const Text('Open'),
            ),
          ),
        ),
        container: container,
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(SnippetPickerPanel), findsOneWidget);
      expect(find.byType(TagChip), findsNothing);
      expect(find.text(t.groups.allGroups), findsNothing);
    },
  );

  testWidgets(
    'long-press enters selection mode and the bar reports "1 selected", and the run sheet does not open',
    (tester) async {
      await pumpSnippets(
        tester,
        snippets: [
          snippetFixture(id: 's1', name: 'Snippet 1'),
          snippetFixture(id: 's2', name: 'Snippet 2'),
        ],
      );

      await tester.longPress(find.text('Snippet 1'));
      await tester.pumpAndSettle();

      expect(
        find.text(t.selection.countSelected(n: 1, count: 1)),
        findsOneWidget,
      );
      expect(find.byType(SelectionActionBar), findsOneWidget);
      expect(find.text(t.snippets.runTitle), findsNothing);
    },
  );

  testWidgets('tapping a second card makes it 2, tapping it again makes it 1', (
    tester,
  ) async {
    await pumpSnippets(
      tester,
      snippets: [
        snippetFixture(id: 's1', name: 'Snippet 1'),
        snippetFixture(id: 's2', name: 'Snippet 2'),
      ],
    );

    await tester.longPress(find.text('Snippet 1'));
    await tester.pumpAndSettle();
    expect(
      find.text(t.selection.countSelected(n: 1, count: 1)),
      findsOneWidget,
    );

    await tester.tap(find.text('Snippet 2'));
    await tester.pumpAndSettle();
    expect(
      find.text(t.selection.countSelected(n: 2, count: 2)),
      findsOneWidget,
    );

    await tester.tap(find.text('Snippet 2'));
    await tester.pumpAndSettle();
    expect(
      find.text(t.selection.countSelected(n: 1, count: 1)),
      findsOneWidget,
    );
  });

  testWidgets(
    'move to group writes the new group onto both selected snippets',
    (tester) async {
      final container = await pumpSnippets(
        tester,
        groups: [
          const ProfileGroup(name: 'General'),
          const ProfileGroup(name: 'DevOps'),
        ],
        snippets: [
          snippetFixture(id: 's1', name: 'Snippet 1', group: 'General'),
          snippetFixture(id: 's2', name: 'Snippet 2', group: 'General'),
        ],
      );

      await tester.longPress(find.text('Snippet 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snippet 2'));
      await tester.pumpAndSettle();

      expect(
        find.text(t.selection.countSelected(n: 2, count: 2)),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(t.selection.moveToGroup));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DevOps'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      final updated = container.read(snippetsProvider);
      expect(updated.firstWhere((s) => s.id == 's1').group, 'DevOps');
      expect(updated.firstWhere((s) => s.id == 's2').group, 'DevOps');

      expect(
        find.text(t.selection.moved(n: 2, count: 2, group: 'DevOps')),
        findsOneWidget,
      );
      expect(find.byType(SelectionActionBar), findsNothing);
    },
  );

  testWidgets('delete asks once and removes both', (tester) async {
    final container = await pumpSnippets(
      tester,
      snippets: [
        snippetFixture(id: 's1', name: 'Snippet 1'),
        snippetFixture(id: 's2', name: 'Snippet 2'),
      ],
    );

    await tester.longPress(find.text('Snippet 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snippet 2'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.common.delete));
    await tester.pumpAndSettle();

    expect(find.text(t.selection.deleteTitle(n: 2, count: 2)), findsOneWidget);
    expect(find.text(t.selection.deleteConfirm), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, t.common.delete));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final remaining = container.read(snippetsProvider);
    expect(remaining, isEmpty);
    expect(find.text('Snippet 1'), findsNothing);
    expect(find.text('Snippet 2'), findsNothing);
    expect(find.text(t.selection.deleted(n: 2, count: 2)), findsOneWidget);
    expect(find.byType(SelectionActionBar), findsNothing);
  });

  testWidgets(
    'clearing the selection leaves selection mode and a tap runs a snippet again',
    (tester) async {
      await pumpSnippets(
        tester,
        snippets: [snippetFixture(id: 's1', name: 'Snippet 1')],
      );

      await tester.longPress(find.text('Snippet 1'));
      await tester.pumpAndSettle();

      expect(
        find.text(t.selection.countSelected(n: 1, count: 1)),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(t.selection.clear));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionActionBar), findsNothing);

      await tester.tap(find.text('Snippet 1'));
      await tester.pumpAndSettle();

      expect(find.text(t.snippets.runTitle), findsOneWidget);
    },
  );
}

/// Puts one snippet on the list without going through the editor - these
/// tests are about the card, not about saving.
Future<void> _seedSnippet(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'snippets': [
      Snippet(
        id: 'snip-1',
        name: 'Restart nginx',
        command: 'sudo systemctl restart nginx',
        createdAt: DateTime(2026),
      ).encode(),
    ],
  });
  SharedPreferences.resetStatic();
  await pumpTestApp(tester, const SnippetsScreen());
  await tester.pumpAndSettle();
}

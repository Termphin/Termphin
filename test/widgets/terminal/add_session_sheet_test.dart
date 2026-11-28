import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/session_tab.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/screens/search/global_search_launcher.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/services/settings/desktop_settings.dart';
import 'package:termphin/widgets/terminal/add_session_sheet.dart';
import 'package:termphin/widgets/ui/app_sheet.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

SessionTab _tab({
  String tabId = 'tab-1',
  String profileId = 'p1',
  String muxName = 'termphin_work',
}) => SessionTab(
  tabId: tabId,
  profileId: profileId,
  muxName: muxName,
  lastSeen: DateTime(2026, 1, 1),
  detached: true,
);

void main() {
  final t = AppLocale.en.buildSync();

  late List<SshProfile> selected;
  late List<(String, String)> attached;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    selected = [];
    attached = [];
  });

  /// A profile whose group is not in the group list is shown under General, so
  /// a test about group chips has to seed the groups it uses.
  Future<void> pump(
    WidgetTester tester,
    List<SshProfile> profiles, {
    Map<String, List<SessionTab>> resumable = const {},
    List<String> groups = const [],
  }) async {
    final container = ProviderContainer.test(
      overrides: [
        groupStorageProvider.overrideWithValue(
          FakeGroupStorage(
            initialGroups: [
              const ProfileGroup(name: 'General'),
              for (final g in groups) ProfileGroup(name: g),
            ],
          ),
        ),
      ],
    );
    await container.read(profileGroupsProvider.notifier).loadGroups();

    await pumpTestApp(
      tester,
      Scaffold(
        body: AddSessionSheetContent(
          profiles: profiles,
          resumableFor: (id) => resumable[id] ?? const [],
          onSelect: selected.add,
          onAttach: (tabId, profile) => attached.add((tabId, profile.id)),
        ),
      ),
      container: container,
    );
    await tester.pumpAndSettle();
  }

  /// The box opens the full-screen search; typing happens there.
  Future<void> search(WidgetTester tester, String query) async {
    if (find.byType(GlobalSearchScreen).evaluate().isEmpty) {
      await tester.tap(find.byType(GlobalSearchLauncher));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('globalSearchField')),
      query,
    );
    await tester.pumpAndSettle();
  }

  List<String> rowOrder(WidgetTester tester, List<String> names) {
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .toList();
    return [
      for (final name in names)
        if (texts.contains(name)) name,
    ]..sort((a, b) => texts.indexOf(a).compareTo(texts.indexOf(b)));
  }

  group('listing machines', () {
    testWidgets('shows every profile it was handed', (tester) async {
      await pump(tester, [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ]);

      expect(find.text(t.terminal.selectDevice), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('says so when there is nothing to show', (tester) async {
      await pump(tester, []);
      expect(find.text(t.terminal.noDevices), findsOneWidget);
    });

    testWidgets('puts the most recently used machine first', (tester) async {
      await pump(tester, [
        profileFixture(
          id: 'old',
          name: 'Older',
          lastConnectedAt: DateTime(2026, 1, 1),
        ),
        profileFixture(
          id: 'new',
          name: 'Newer',
          lastConnectedAt: DateTime(2026, 6, 1),
        ),
      ]);

      expect(rowOrder(tester, ['Newer', 'Older']), ['Newer', 'Older']);
    });

    testWidgets('falls back to when it was created, never connected', (
      tester,
    ) async {
      await pump(tester, [
        profileFixture(
          id: 'a',
          name: 'MadeFirst',
          createdAt: DateTime(2026, 1),
        ),
        profileFixture(
          id: 'b',
          name: 'MadeLater',
          createdAt: DateTime(2026, 5),
        ),
      ]);

      expect(rowOrder(tester, ['MadeLater', 'MadeFirst']), [
        'MadeLater',
        'MadeFirst',
      ]);
    });

    testWidgets('breaks a tie by name', (tester) async {
      final same = DateTime(2026, 3, 3);
      await pump(tester, [
        profileFixture(id: 'z', name: 'Zulu', lastConnectedAt: same),
        profileFixture(id: 'a', name: 'Alpha', lastConnectedAt: same),
      ]);

      expect(rowOrder(tester, ['Alpha', 'Zulu']), ['Alpha', 'Zulu']);
    });
  });

  group('searching', () {
    testWidgets('matches the machine name', (tester) async {
      await pump(tester, [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ]);
      await search(tester, 'alp');

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('matches the host and the username too', (tester) async {
      await pump(tester, [
        profileFixture(id: 'p1', name: 'Alpha', host: 'db.internal'),
        profileFixture(id: 'p2', name: 'Beta', username: 'releasebot'),
      ]);

      await search(tester, 'db.int');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);

      await search(tester, 'releasebot');
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('matches a group', (tester) async {
      await pump(
        tester,
        [
          profileFixture(id: 'p1', name: 'Alpha', group: 'prod'),
          profileFixture(id: 'p2', name: 'Beta', group: 'staging'),
        ],
        groups: ['prod', 'staging'],
      );
      await search(tester, 'prod');

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('lists only machines, every one of them', (tester) async {
      await pump(tester, [
        for (var i = 0; i < 7; i++) profileFixture(id: 'p$i', name: 'Box $i'),
      ]);
      await tester.tap(find.byType(GlobalSearchLauncher));
      await tester.pumpAndSettle();

      expect(find.byType(GlobalSearchScreen), findsOneWidget);
      expect(find.text('Box 6', skipOffstage: false), findsWidgets);
      expect(find.text(t.globalSearch.emptyHint), findsNothing);
    });

    testWidgets('a machine picked there starts a new session on it', (
      tester,
    ) async {
      await pump(tester, [
        profileFixture(id: 'p1', name: 'Alpha'),
        profileFixture(id: 'p2', name: 'Beta'),
      ]);
      await search(tester, 'bet');
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(selected.map((p) => p.id), ['p2']);
      expect(find.byType(GlobalSearchScreen), findsNothing);
    });

    testWidgets('ignores case', (tester) async {
      await pump(tester, [profileFixture(id: 'p1', name: 'Alpha')]);
      await search(tester, 'ALPHA');
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pump(tester, [profileFixture(id: 'p1', name: 'Alpha')]);
      await search(tester, 'nothing like this');
      expect(
        find.text(t.globalSearch.noResults(query: 'nothing like this')),
        findsOneWidget,
      );
    });
  });

  group('filtering by group', () {
    testWidgets('offers every group in use, plus All', (tester) async {
      await pump(
        tester,
        [
          profileFixture(id: 'p1', name: 'Alpha', group: 'prod'),
          profileFixture(id: 'p2', name: 'Beta', group: 'eu'),
        ],
        groups: ['prod', 'eu'],
      );

      expect(find.text(t.groups.allGroups), findsOneWidget);
      expect(find.text('prod'), findsWidgets);
      expect(find.text('eu'), findsWidgets);
    });

    testWidgets('shows no group bar when profiles list is empty', (
      tester,
    ) async {
      await pump(tester, []);
      expect(find.text(t.groups.allGroups), findsNothing);
    });

    testWidgets(
      'narrows the list to the group tapped, and All brings it back',
      (tester) async {
        await pump(
          tester,
          [
            profileFixture(id: 'p1', name: 'Alpha', group: 'prod'),
            profileFixture(id: 'p2', name: 'Beta', group: 'staging'),
          ],
          groups: ['prod', 'staging'],
        );

        await tester.tap(find.text('staging').first);
        await tester.pumpAndSettle();
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Alpha'), findsNothing);

        await tester.tap(find.text(t.groups.allGroups));
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
      },
    );
  });

  group('picking something', () {
    testWidgets('tapping a machine asks for a new session on it', (
      tester,
    ) async {
      await pump(tester, [profileFixture(id: 'p1', name: 'Alpha')]);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(selected.map((p) => p.id), ['p1']);
      expect(attached, isEmpty);
    });

    testWidgets('a waiting session is listed under its machine', (
      tester,
    ) async {
      await pump(
        tester,
        [profileFixture(id: 'p1', name: 'Alpha')],
        resumable: {
          'p1': [_tab(muxName: 'termphin_work')],
        },
      );

      expect(find.text('work'), findsOneWidget);
      expect(find.text('termphin_work'), findsNothing);
    });

    testWidgets('tapping a waiting session re-attaches it instead', (
      tester,
    ) async {
      await pump(
        tester,
        [profileFixture(id: 'p1', name: 'Alpha')],
        resumable: {
          'p1': [_tab(tabId: 'tab-7', muxName: 'termphin_work')],
        },
      );

      await tester.tap(find.text('work'));
      await tester.pumpAndSettle();

      expect(attached, [('tab-7', 'p1')]);
      expect(selected, isEmpty);
    });

    testWidgets('lists every waiting session on the machine', (tester) async {
      await pump(
        tester,
        [profileFixture(id: 'p1', name: 'Alpha')],
        resumable: {
          'p1': [
            _tab(tabId: 'a', muxName: 'termphin_one'),
            _tab(tabId: 'b', muxName: 'termphin_two'),
          ],
        },
      );

      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
    });
  });

  group('from the keyboard on a desktop', () {
    const desktop = TargetPlatformVariant({TargetPlatform.linux});
    final machines = [
      profileFixture(id: 'p1', name: 'Alpha'),
      profileFixture(id: 'p2', name: 'Bravo'),
    ];

    testWidgets('typing starts a search that takes the next keys', (
      tester,
    ) async {
      await pump(tester, machines);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();

      expect(find.byType(GlobalSearchScreen), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('globalSearchField')),
      );
      expect(field.controller!.text, 'b');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 1),
      );
    }, variant: desktop);

    testWidgets('the arrows walk the machines and Enter picks one', (
      tester,
    ) async {
      await pump(tester, machines);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(selected.map((p) => p.name), ['Alpha']);
    }, variant: desktop);

    testWidgets(
      'Escape with a GTK \\x1b character closes the sheet without searching',
      (tester) async {
        final container = ProviderContainer.test(
          overrides: [
            groupStorageProvider.overrideWithValue(
              FakeGroupStorage(
                initialGroups: const [ProfileGroup(name: 'General')],
              ),
            ),
          ],
        );
        await container.read(profileGroupsProvider.notifier).loadGroups();

        late BuildContext rootContext;
        await pumpTestApp(
          tester,
          Builder(
            builder: (context) {
              rootContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
          container: container,
        );
        await tester.pumpAndSettle();

        final sheetFuture = showAppSheet<void>(
          context: rootContext,
          handle: false,
          builder: (_) => AddSessionSheetContent(
            profiles: machines,
            resumableFor: (_) => const [],
            onSelect: selected.add,
            onAttach: (_, _) {},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddSessionSheetContent), findsOneWidget);

        final sheetFocus = tester.widget<Focus>(
          find
              .descendant(
                of: find.byType(AddSessionSheetContent),
                matching: find.byWidgetPredicate(
                  (w) => w is Focus && w.onKeyEvent != null,
                ),
              )
              .first,
        );
        final handled = sheetFocus.onKeyEvent!(
          sheetFocus.focusNode ?? FocusNode(),
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.escape,
            logicalKey: LogicalKeyboardKey.escape,
            character: '\x1b',
            timeStamp: Duration.zero,
          ),
        );
        expect(handled, KeyEventResult.ignored);
        await tester.pump();
        expect(find.byType(GlobalSearchScreen), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(GlobalSearchScreen), findsNothing);
        expect(find.byType(AddSessionSheetContent), findsNothing);
        await sheetFuture;
      },
      variant: desktop,
    );
  });

  group('This computer in the picker', () {
    const desktop = TargetPlatformVariant({TargetPlatform.linux});

    testWidgets(
      'pins This computer first without a :0 port and hides it under group filters',
      (tester) async {
        final local = localComputerProfile(
          name: t.profiles.thisComputer,
          host: 'workstation',
          username: 'alice',
        );
        await pump(
          tester,
          [
            local,
            profileFixture(id: 'p1', name: 'Alpha', group: 'Staging'),
            profileFixture(id: 'p2', name: 'Beta', group: 'Prod'),
          ],
          groups: ['Staging', 'Prod'],
        );

        expect(rowOrder(tester, [t.profiles.thisComputer, 'Alpha', 'Beta']), [
          t.profiles.thisComputer,
          'Alpha',
          'Beta',
        ]);
        expect(find.text('alice@workstation'), findsOneWidget);
        expect(find.text('alice@workstation:0'), findsNothing);
        expect(find.text('General'), findsNothing);

        await tester.tap(find.text('Staging').first);
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsNothing);
        expect(find.text(t.profiles.thisComputer), findsNothing);
      },
      variant: desktop,
    );

    testWidgets(
      'sessionPickerProfiles prepends This computer when enabled on a desktop',
      (tester) async {
        await showThisComputerSetting.set(true);
        final container = ProviderContainer.test(
          overrides: [
            profileStorageProvider.overrideWithValue(
              FakeProfileStorage([profileFixture(id: 'p1', name: 'Alpha')]),
            ),
            localSessionsSupportedProvider.overrideWith((ref) async => true),
          ],
        );
        await container.read(profilesProvider.notifier).loadProfiles();
        await container.read(localSessionsSupportedProvider.future);

        late List<SshProfile> picked;
        await pumpTestApp(
          tester,
          Consumer(
            builder: (context, ref, _) {
              picked = sessionPickerProfiles(ref, t);
              return const SizedBox.shrink();
            },
          ),
          container: container,
        );

        expect(picked.map((p) => p.id), [kLocalProfileId, 'p1']);
      },
      variant: desktop,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/snippets_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/providers/terminal_overlay_provider.dart';
import 'package:termphin/screens/search/global_search_launcher.dart';
import 'package:termphin/screens/search/global_search_screen.dart';
import 'package:termphin/services/app/identity_anonymizer.dart';
import 'package:termphin/services/settings/anonymize_setting.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  final web = profileFixture(
    id: 'web',
    name: 'web-1',
    host: '10.0.0.4',
    username: 'root',
    group: 'Production',
  );
  final pi = profileFixture(
    id: 'pi',
    name: 'raspberry',
    host: '192.168.1.20',
    username: 'pi',
  );
  final restart = snippetFixture(
    id: 's1',
    name: 'Restart nginx',
    command: 'systemctl restart nginx',
    group: 'Production',
  );
  final laptop = sshKeyFixture(id: 'k1', name: 'laptop');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await anonymizeSetting.load();
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    final profiles = FakeProfileStorage([web, pi]);
    final keys = FakeSshKeyStorage([laptop]);
    final groups = FakeGroupStorage(
      initialGroups: const [
        ProfileGroup(name: 'General'),
        ProfileGroup(name: 'Production', colorHex: '4DA3FF'),
      ],
      profilesStorage: profiles,
      keysStorage: keys,
    );
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(profiles),
        sshKeyStorageProvider.overrideWithValue(keys),
        groupStorageProvider.overrideWithValue(groups),
        snippetStorageProvider.overrideWithValue(FakeSnippetStorage([restart])),
      ],
    );
    await container.read(profilesProvider.notifier).loadProfiles();
    await container.read(profileGroupsProvider.notifier).loadGroups();
    await container.read(snippetsProvider.notifier).loadSnippets();

    await pumpTestApp(
      tester,
      const Scaffold(body: GlobalSearchLauncher(heroTag: 'test-search')),
      container: container,
    );
    await tester.tap(find.byType(GlobalSearchLauncher));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('globalSearchField')),
      query,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the box flies up into a focused field', (tester) async {
    await open(tester);

    expect(find.byType(GlobalSearchScreen), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('globalSearchField')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('finds a machine by its address and a snippet by its command', (
    tester,
  ) async {
    await open(tester);

    await type(tester, '192.168');
    expect(find.text('raspberry'), findsOneWidget);
    expect(find.text('web-1'), findsNothing);

    await type(tester, 'systemctl');
    expect(find.text('Restart nginx'), findsOneWidget);
    expect(find.text(t.globalSearch.snippets.toUpperCase()), findsOneWidget);
  });

  testWidgets('the section with the best match comes first', (tester) async {
    await open(tester);

    await type(tester, 'prod');
    double top(String header) =>
        tester.getTopLeft(find.text(header.toUpperCase())).dy;
    expect(top(t.globalSearch.groups), lessThan(top(t.globalSearch.machines)));
  });

  testWidgets('a group narrows the search to itself until the chip is closed', (
    tester,
  ) async {
    await open(tester);

    await type(tester, 'prod');
    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();

    expect(
      find.text(t.globalSearch.inGroup(group: 'Production')),
      findsOneWidget,
    );
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('Restart nginx'), findsOneWidget);
    expect(find.text('raspberry'), findsNothing);
    expect(find.text('laptop'), findsNothing);

    await tester.tap(find.byTooltip(t.globalSearch.leaveGroup));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globalSearchScope')), findsNothing);
  });

  testWidgets('a machine closes the search and opens in the terminal', (
    tester,
  ) async {
    final container = await open(tester);

    await type(tester, 'root');
    await tester.tap(find.text('web-1'));
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSearchScreen), findsNothing);
    expect(container.read(terminalOverlayProvider)?.$2.id, 'web');
  });

  /// The box between the two routes: a [SearchBox] belonging to neither end
  /// is the one in the air.
  Finder flyingBox() =>
      find.byWidgetPredicate((w) => w is SearchBox).evaluate().where((e) {
        var inEnd = false;
        e.visitAncestorElements((a) {
          if (a.widget is GlobalSearchLauncher ||
              a.widget is GlobalSearchScreen) {
            inEnd = true;
            return false;
          }
          return true;
        });
        return !inEnd;
      }).isNotEmpty
      ? find.byType(SearchBox)
      : find.byKey(const ValueKey('no-flight'));

  testWidgets('back flies the box down to the list again', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip(t.globalSearch.back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(flyingBox(), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('opening a machine leaves the box where it is', (tester) async {
    await open(tester);

    await type(tester, 'root');
    await tester.tap(find.text('web-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(flyingBox(), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('says so when nothing matches', (tester) async {
    await open(tester);

    await type(tester, 'nothing here');

    expect(
      find.text(t.globalSearch.noResults(query: 'nothing here')),
      findsOneWidget,
    );
  });

  testWidgets('anonymize hides the real name and address it matched on', (
    tester,
  ) async {
    await anonymizeSetting.set(true);
    addTearDown(() => anonymizeSetting.set(false));
    await open(tester);

    await type(tester, '10.0.0.4');

    final results = find.byType(ListView);
    expect(
      find.descendant(
        of: results,
        matching: find.text(IdentityAnonymizer.name('web')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: results, matching: find.textContaining('web-1')),
      findsNothing,
    );
    expect(
      find.descendant(of: results, matching: find.textContaining('10.0.0.4')),
      findsNothing,
    );
  });
}

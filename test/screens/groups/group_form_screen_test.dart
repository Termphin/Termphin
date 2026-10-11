import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/screens/groups/group_form_screen.dart';
import 'package:termphin/widgets/profiles/profile_avatar.dart';

import '../../support/fakes.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProviderContainer, FakeGroupStorage)> pumpGroupForm(
    WidgetTester tester, {
    List<ProfileGroup> existingGroups = const [ProfileGroup(name: 'General')],
    ProfileGroup? editingGroup,
    bool showManageGroups = false,
  }) async {
    final fakeGroups = FakeGroupStorage(initialGroups: existingGroups);
    final container = ProviderContainer.test(
      overrides: [groupStorageProvider.overrideWithValue(fakeGroups)],
    );

    await container.read(profileGroupsProvider.notifier).loadGroups();

    await pumpTestApp(
      tester,
      GroupFormScreen(
        existing: editingGroup,
        showManageGroups: showManageGroups,
      ),
      container: container,
    );
    await tester.pumpAndSettle();

    return (container, fakeGroups);
  }

  group('GroupFormScreen', () {
    testWidgets('creates a group with a colour', (tester) async {
      final (_, fakeGroups) = await pumpGroupForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('groupNameField')),
        'Database Servers',
      );
      await tester.pumpAndSettle();

      final targetColor = ProfileAvatarColor.colors[2];
      final colorFinder = find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == targetColor.color,
      );
      expect(colorFinder, findsOneWidget);
      await tester.tap(colorFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await fakeGroups.loadGroups();
      expect(stored.map((g) => g.name), contains('Database Servers'));
      final created = stored.firstWhere((g) => g.name == 'Database Servers');
      expect(created.colorHex, targetColor.hex);
    });

    testWidgets(
      'new group opens with a colour preselected that is not already taken',
      (tester) async {
        final firstColor = ProfileAvatarColor.colors.first;
        final secondColor = ProfileAvatarColor.colors[1];
        final (_, fakeGroups) = await pumpGroupForm(
          tester,
          existingGroups: [
            const ProfileGroup(name: 'General'),
            ProfileGroup(name: 'Staging', colorHex: firstColor.hex),
          ],
        );

        final selectedColorFinder = find.byWidgetPredicate(
          (w) =>
              w is AnimatedContainer &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == secondColor.color &&
              w.child is Icon,
        );
        expect(selectedColorFinder, findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('groupNameField')),
          'Production',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final stored = await fakeGroups.loadGroups();
        final created = stored.firstWhere((g) => g.name == 'Production');
        expect(created.colorHex, secondColor.hex);
      },
    );

    testWidgets(
      'new group falls back to first colour when all colours are taken',
      (tester) async {
        final allColorGroups = [
          const ProfileGroup(name: 'General'),
          for (var i = 0; i < ProfileAvatarColor.colors.length; i++)
            ProfileGroup(
              name: 'Group $i',
              colorHex: ProfileAvatarColor.colors[i].hex,
            ),
        ];

        final (_, fakeGroups) = await pumpGroupForm(
          tester,
          existingGroups: allColorGroups,
        );

        await tester.enterText(
          find.byKey(const ValueKey('groupNameField')),
          'Overflow Group',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final stored = await fakeGroups.loadGroups();
        final created = stored.firstWhere((g) => g.name == 'Overflow Group');
        expect(created.colorHex, ProfileAvatarColor.colors.first.hex);
      },
    );

    testWidgets(
      'picking the "no colour" tile and saving stores a null colorHex',
      (tester) async {
        final t = AppLocale.en.buildSync();
        final (_, fakeGroups) = await pumpGroupForm(tester);

        await tester.enterText(
          find.byKey(const ValueKey('groupNameField')),
          'Plain Group',
        );
        await tester.pumpAndSettle();

        final noColourFinder = find.byTooltip(t.groups.noColour);
        expect(noColourFinder, findsOneWidget);
        await tester.tap(noColourFinder);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final stored = await fakeGroups.loadGroups();
        final created = stored.firstWhere((g) => g.name == 'Plain Group');
        expect(created.colorHex, isNull);
      },
    );

    testWidgets(
      'editing an existing group does not change its stored colour when only editing name',
      (tester) async {
        final existingColor = ProfileAvatarColor.colors[2];
        final (_, fakeGroups) = await pumpGroupForm(
          tester,
          existingGroups: [
            const ProfileGroup(name: 'General'),
            ProfileGroup(name: 'Staging', colorHex: existingColor.hex),
          ],
          editingGroup: ProfileGroup(
            name: 'Staging',
            colorHex: existingColor.hex,
          ),
        );

        await tester.enterText(
          find.byKey(const ValueKey('groupNameField')),
          'Staging V2',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final stored = await fakeGroups.loadGroups();
        final updated = stored.firstWhere((g) => g.name == 'Staging V2');
        expect(updated.colorHex, existingColor.hex);
      },
    );

    testWidgets(
      'manage-groups icon is absent by default and present when showManageGroups is true',
      (tester) async {
        await pumpGroupForm(tester);
        expect(
          find.byIcon(PhosphorIconsRegular.slidersHorizontal),
          findsNothing,
        );

        await pumpGroupForm(tester, showManageGroups: true);
        expect(
          find.byIcon(PhosphorIconsRegular.slidersHorizontal),
          findsOneWidget,
        );
      },
    );

    testWidgets('the preview follows the name being typed', (tester) async {
      await pumpGroupForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('groupNameField')),
        'Bastions',
      );
      await tester.pumpAndSettle();

      expect(find.text('Bastions'), findsNWidgets(2));
    });

    testWidgets('editing a group offers delete, and General does not', (
      tester,
    ) async {
      final t = AppLocale.en.buildSync();
      final (_, fakeGroups) = await pumpGroupForm(
        tester,
        existingGroups: const [
          ProfileGroup(name: 'General'),
          ProfileGroup(name: 'Staging'),
        ],
        editingGroup: const ProfileGroup(name: 'Staging'),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, t.common.delete));
      await tester.pumpAndSettle();

      expect(find.text(t.groups.deleteTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, t.common.delete));
      await tester.pumpAndSettle();

      final stored = await fakeGroups.loadGroups();
      expect(stored.map((g) => g.name), isNot(contains('Staging')));
    });

    testWidgets('General cannot be deleted from the form', (tester) async {
      final t = AppLocale.en.buildSync();
      await pumpGroupForm(
        tester,
        editingGroup: const ProfileGroup(name: 'General'),
      );

      expect(
        find.widgetWithText(OutlinedButton, t.common.delete),
        findsNothing,
      );
    });

    testWidgets('refuses case-insensitive duplicate name', (tester) async {
      final t = AppLocale.en.buildSync();
      final (_, fakeGroups) = await pumpGroupForm(
        tester,
        existingGroups: const [
          ProfileGroup(name: 'General'),
          ProfileGroup(name: 'Staging', colorHex: '4DA3FF'),
        ],
      );

      await tester.enterText(
        find.byKey(const ValueKey('groupNameField')),
        'staging',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(t.groups.alreadyExists), findsOneWidget);

      final stored = await fakeGroups.loadGroups();
      expect(stored.length, 2);
    });
  });
}

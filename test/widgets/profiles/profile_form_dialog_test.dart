import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:termphin/services/settings/profile_form_settings.dart';
import 'package:termphin/services/ssh/ssh_link.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/widgets/groups/group_picker_field.dart';
import 'package:termphin/widgets/profiles/profile_form_dialog.dart';
import 'package:termphin/widgets/ui/section_header.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

Finder _formField(String label) {
  return find.widgetWithText(TextFormField, label);
}

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final finder = _formField(label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

/// Scrolls the row well clear of the bottom edge, where a row scrolled just
/// into view is not hittable, then taps it.
Future<void> _tapInForm(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    await profileFormMoreOptionsSetting.load();
  });

  /// The form's own list, not the row of avatars across its top.
  final formList = find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;

  /// Opens "More options", where the jump host and the rest live.
  Future<void> openMoreOptions(WidgetTester tester) async {
    final header = find.text(t.profileForm.moreOptions);
    await tester.scrollUntilVisible(header, 250, scrollable: formList);
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Future<
    (ProviderContainer, FakeProfileStorage, FakeSshKeyStorage, FakeGroupStorage)
  >
  pumpProfileForm(
    WidgetTester tester, {
    SshProfile? profile,
    String? initialGroup,
    List<ProfileGroup> groups = const [
      ProfileGroup(name: 'General'),
      ProfileGroup(name: 'Servers', colorHex: '4DA3FF'),
      ProfileGroup(name: 'Staging', colorHex: '52C41A'),
    ],
    List<SshProfile> profiles = const [],
    List<SshKey> keys = const [],
  }) async {
    final fakeProfiles = FakeProfileStorage(profiles);
    final fakeKeys = FakeSshKeyStorage(keys);
    final fakeGroups = FakeGroupStorage(
      initialGroups: groups,
      profilesStorage: fakeProfiles,
      keysStorage: fakeKeys,
    );
    final container = ProviderContainer.test(
      overrides: [
        profileStorageProvider.overrideWithValue(fakeProfiles),
        sshKeyStorageProvider.overrideWithValue(fakeKeys),
        groupStorageProvider.overrideWithValue(fakeGroups),
      ],
    );

    await container.read(profileGroupsProvider.notifier).loadGroups();
    await container.read(profilesProvider.notifier).loadProfiles();

    await pumpTestApp(
      tester,
      ProfileFormDialog(profile: profile, initialGroup: initialGroup),
      container: container,
    );
    await tester.pumpAndSettle();

    return (container, fakeProfiles, fakeKeys, fakeGroups);
  }

  group('test connection', () {
    Future<List<SshProfile>> pumpWithTest(
      WidgetTester tester,
      Future<void> Function(SshProfile) test,
    ) async {
      final tried = <SshProfile>[];
      final container = ProviderContainer.test(
        overrides: [
          profileStorageProvider.overrideWithValue(FakeProfileStorage()),
          connectionTestProvider.overrideWithValue((profile, cancel) {
            tried.add(profile);
            return test(profile);
          }),
        ],
      );
      await pumpTestApp(
        tester,
        const ProfileFormDialog(),
        container: container,
      );
      await tester.pumpAndSettle();
      await _enterField(tester, 'Host', 'server.example.com');
      await _enterField(tester, 'Port', '2202');
      await _enterField(tester, 'Username', 'deploy');
      await _tapInForm(tester, find.text(t.profileForm.noAuth));
      return tried;
    }

    Future<void> tapTest(WidgetTester tester) =>
        _tapInForm(tester, find.text(t.profileForm.testConnection));

    testWidgets('tries the fields as they are, without saving', (tester) async {
      final tried = await pumpWithTest(tester, (_) async {});

      await tapTest(tester);

      expect(find.text(t.profileForm.testSucceeded), findsOneWidget);
      expect(tried.single.host, 'server.example.com');
      expect(tried.single.port, 2202);
      expect(tried.single.username, 'deploy');
    });

    testWidgets('says why it failed', (tester) async {
      await pumpWithTest(
        tester,
        (_) async => throw const SshConnectException(
          SshFailureReason.hostUnreachable,
          'Could not reach server.example.com.',
        ),
      );

      await tapTest(tester);

      expect(find.text('Could not reach server.example.com.'), findsOneWidget);
      expect(find.text(t.profileForm.testSucceeded), findsNothing);
    });
  });

  testWidgets('a new machine keeps the advanced options folded away until '
      'asked, and the form remembers they were opened', (tester) async {
    await pumpProfileForm(tester);
    await tester.scrollUntilVisible(
      find.text(t.profileForm.moreOptionsHint),
      250,
      scrollable: formList,
    );

    expect(find.text(t.profileForm.jumpHostNone), findsNothing);

    await openMoreOptions(tester);
    await tester.scrollUntilVisible(
      find.text(t.profileForm.jumpHostNone),
      250,
      scrollable: formList,
    );

    expect(find.text(t.profileForm.jumpHostNone), findsOneWidget);
    expect(profileFormMoreOptionsSetting.value, isTrue);
  });

  testWidgets('a machine that uses a jump host opens with it shown and named', (
    tester,
  ) async {
    final bastion = profileFixture(id: 'bastion', name: 'Bastion');
    final current = profileFixture(
      id: 'current',
      name: 'Current',
      jumpHostProfileId: 'bastion',
    );

    await pumpProfileForm(
      tester,
      profile: current,
      profiles: [current, bastion],
    );
    await tester.scrollUntilVisible(
      find.text(t.profileForm.moreJumpHost(name: 'Bastion')),
      250,
      scrollable: formList,
    );
    await tester.scrollUntilVisible(
      find.text(t.profileForm.fallbackHostsEmpty),
      250,
      scrollable: formList,
    );

    expect(find.text(t.profileForm.fallbackHostsEmpty), findsOneWidget);
    expect(
      find.text(t.profileForm.moreJumpHost(name: 'Bastion')),
      findsOneWidget,
    );
  });

  testWidgets('validates required connection fields before saving', (
    tester,
  ) async {
    final storage = FakeProfileStorage();
    final container = ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
    await pumpTestApp(tester, const ProfileFormDialog(), container: container);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();

    expect(find.text('Required'), findsNWidgets(2));
    expect(storage.addCount, 0);
  });

  testWidgets('a typed user@host does not pick a sign-in method for you', (
    tester,
  ) async {
    final storage = FakeProfileStorage();
    final container = ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
    await pumpTestApp(
      tester,
      const ProfileFormDialog(
        prefill: SshLink(host: 'devbox', user: 'alice'),
      ),
      container: container,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text(t.profileForm.chooseAuth), findsWidgets);
    expect(storage.addCount, 0);
  });

  testWidgets('creates a trimmed profile without authentication', (
    tester,
  ) async {
    final storage = FakeProfileStorage();
    final container = ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
    await pumpTestApp(tester, const ProfileFormDialog(), container: container);
    await tester.pumpAndSettle();

    await _enterField(tester, 'Name', '  Production  ');
    await _enterField(tester, 'Host', '  server.example.com  ');
    await _enterField(tester, 'Port', '2202');
    await _enterField(tester, 'Username', '  deploy  ');
    await _tapInForm(tester, find.text(t.profileForm.noAuth));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(storage.addCount, 1);
    expect(storage.profiles, hasLength(1));
    final profile = storage.profiles.single;
    expect(profile.name, 'Production');
    expect(profile.host, 'server.example.com');
    expect(profile.port, 2202);
    expect(profile.username, 'deploy');
    expect(profile.authMethod, AuthMethod.none);
    expect(profile.password, isNull);
  });

  testWidgets('Ctrl+S saves, as the Save button does', (tester) async {
    final storage = FakeProfileStorage();
    final container = ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
    await pumpTestApp(tester, const SizedBox.expand(), container: container);
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(builder: (_) => const ProfileFormDialog()),
          ),
    );
    await tester.pumpAndSettle();

    await _enterField(tester, 'Host', 'server.example.com');
    await _enterField(tester, 'Username', 'deploy');
    await _tapInForm(tester, find.text(t.profileForm.noAuth));
    await tester.tap(_formField('Username'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(storage.addCount, 1);
    expect(storage.profiles.single.host, 'server.example.com');
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('a key created from the form is picked for the machine', (
    tester,
  ) async {
    final (_, profiles, keys, _) = await pumpProfileForm(tester);

    await _enterField(tester, 'Name', 'Production');
    await _enterField(tester, 'Host', 'server.example.com');
    await _enterField(tester, 'Username', 'deploy');
    await _tapInForm(tester, find.text(t.profileForm.sshKey));
    await _tapInForm(tester, find.text(t.profileForm.createKey));

    expect(find.byType(KeyFormScreen), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Production'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Save').last);
    await tester.pumpAndSettle();

    expect(keys.generateEd25519Count, 1);
    expect(find.text(t.keys.keyCreatedTitle), findsOneWidget);
    await tester.tap(find.text(t.common.done));
    await tester.pumpAndSettle();
    expect(find.byType(KeyFormScreen), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = profiles.profiles.single;
    expect(saved.authMethod, AuthMethod.privateKey);
    expect(saved.sshKeyId, keys.keys.single.id);
  });

  testWidgets('changing to no authentication removes the stored password', (
    tester,
  ) async {
    final existing = profileFixture(
      authMethod: AuthMethod.password,
      password: 'old-secret',
    );
    final storage = FakeProfileStorage([existing]);
    final container = ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
    await pumpTestApp(
      tester,
      ProfileFormDialog(profile: existing),
      container: container,
    );
    await tester.pumpAndSettle();

    final noAuthentication = find.text('No authentication');
    await tester.scrollUntilVisible(
      noAuthentication,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(noAuthentication);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(storage.updateCount, 1);
    expect(storage.profiles.single.authMethod, AuthMethod.none);
    expect(storage.profiles.single.password, isNull);
  });

  group('group-aware pickers', () {
    testWidgets(
      'with keys in two groups, the keys in the machine\'s group render before the others and the otherGroups header sits between them',
      (tester) async {
        final keySame = sshKeyFixture(
          id: 'k-same',
          name: 'Same Group Key',
          group: 'General',
        );
        final keyOther = sshKeyFixture(
          id: 'k-other',
          name: 'Other Group Key',
          group: 'Servers',
        );

        final profile = profileFixture(
          authMethod: AuthMethod.privateKey,
          group: 'General',
        );

        await pumpProfileForm(
          tester,
          profile: profile,
          keys: [keyOther, keySame],
        );

        final keySameFinder = find.text('Same Group Key');
        final keyOtherFinder = find.text('Other Group Key');
        final headerFinder = find.widgetWithText(
          SectionHeader,
          t.groups.otherGroups.toUpperCase(),
        );

        await tester.scrollUntilVisible(
          keyOtherFinder,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(keySameFinder, findsOneWidget);
        expect(headerFinder, findsOneWidget);
        expect(keyOtherFinder, findsOneWidget);

        final sameY = tester.getTopLeft(keySameFinder).dy;
        final headerY = tester.getTopLeft(headerFinder).dy;
        final otherY = tester.getTopLeft(keyOtherFinder).dy;

        expect(sameY, lessThan(headerY));
        expect(headerY, lessThan(otherY));

        await tester.tap(keyOtherFinder);
        await tester.pumpAndSettle();
        final keyCheck = find.byWidgetPredicate(
          (w) =>
              w is Icon && w.icon == PhosphorIconsRegular.check && w.size == 12,
        );
        expect(keyCheck, findsOneWidget);
        expect(
          tester.getTopLeft(keyCheck).dy,
          closeTo(tester.getTopLeft(keyOtherFinder).dy, 20),
        );
      },
    );

    testWidgets('with every key in the machine\'s group, no header is drawn', (
      tester,
    ) async {
      final keyA = sshKeyFixture(
        id: 'k-a',
        name: 'Key Alpha',
        group: 'General',
      );
      final keyB = sshKeyFixture(id: 'k-b', name: 'Key Beta', group: 'General');

      final profile = profileFixture(
        authMethod: AuthMethod.privateKey,
        group: 'General',
      );

      await pumpProfileForm(tester, profile: profile, keys: [keyA, keyB]);

      await tester.scrollUntilVisible(
        find.text('Key Beta'),
        250,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Key Alpha'), findsOneWidget);
      expect(find.text('Key Beta'), findsOneWidget);
      expect(
        find.widgetWithText(SectionHeader, t.groups.otherGroups.toUpperCase()),
        findsNothing,
      );
    });

    testWidgets(
      'with every key outside the machine\'s group, no header is drawn',
      (tester) async {
        final keyOther1 = sshKeyFixture(
          id: 'k-other-1',
          name: 'Other One',
          group: 'Servers',
        );
        final keyOther2 = sshKeyFixture(
          id: 'k-other-2',
          name: 'Other Two',
          group: 'Staging',
        );

        final profile = profileFixture(
          authMethod: AuthMethod.privateKey,
          group: 'General',
        );

        await pumpProfileForm(
          tester,
          profile: profile,
          keys: [keyOther1, keyOther2],
        );

        await tester.scrollUntilVisible(
          find.text('Other Two'),
          250,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('Other One'), findsOneWidget);
        expect(find.text('Other Two'), findsOneWidget);
        expect(
          find.widgetWithText(
            SectionHeader,
            t.groups.otherGroups.toUpperCase(),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'changing the group in the form\'s group picker re-orders the key list',
      (tester) async {
        final keyGen = sshKeyFixture(
          id: 'k-gen',
          name: 'Key Gen',
          group: 'General',
        );
        final keySrv = sshKeyFixture(
          id: 'k-srv',
          name: 'Key Srv',
          group: 'Servers',
        );

        final profile = profileFixture(
          authMethod: AuthMethod.privateKey,
          group: 'General',
        );

        await pumpProfileForm(tester, profile: profile, keys: [keyGen, keySrv]);

        final keyGenFinder = find.text('Key Gen');
        final keySrvFinder = find.text('Key Srv');
        final headerFinder = find.widgetWithText(
          SectionHeader,
          t.groups.otherGroups.toUpperCase(),
        );

        await tester.scrollUntilVisible(
          keySrvFinder,
          250,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          tester.getTopLeft(keyGenFinder).dy,
          lessThan(tester.getTopLeft(headerFinder).dy),
        );
        expect(
          tester.getTopLeft(headerFinder).dy,
          lessThan(tester.getTopLeft(keySrvFinder).dy),
        );

        await tester.scrollUntilVisible(
          find.byType(GroupPickerField),
          -250,
          scrollable: find.byType(Scrollable).first,
        );

        await tester.ensureVisible(find.byType(GroupPickerField));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(GroupPickerField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Servers').last);
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          keyGenFinder,
          250,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          tester.getTopLeft(keySrvFinder).dy,
          lessThan(tester.getTopLeft(headerFinder).dy),
        );
        expect(
          tester.getTopLeft(headerFinder).dy,
          lessThan(tester.getTopLeft(keyGenFinder).dy),
        );
      },
    );

    testWidgets('the jump-host list orders the same way', (tester) async {
      final currentProfile = profileFixture(
        id: 'prof-curr',
        name: 'Current Machine',
        group: 'General',
      );
      final jhSame = profileFixture(
        id: 'jh-same',
        name: 'JumpHost Same Group',
        group: 'General',
        host: 'same.example.com',
      );
      final jhOther = profileFixture(
        id: 'jh-other',
        name: 'JumpHost Other Group',
        group: 'Servers',
        host: 'other.example.com',
      );
      final jhLoop = profileFixture(
        id: 'jh-loop',
        name: 'JumpHost Looping',
        group: 'General',
        host: 'loop.example.com',
        jumpHostProfileId: 'prof-curr',
      );

      await pumpProfileForm(
        tester,
        profile: currentProfile,
        profiles: [currentProfile, jhOther, jhSame, jhLoop],
      );

      await openMoreOptions(tester);
      final jumpHostTile = find.text(t.profileForm.jumpHostNone);
      await tester.scrollUntilVisible(
        jumpHostTile,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(jumpHostTile);
      await tester.pumpAndSettle();

      expect(find.text('JumpHost Looping'), findsNothing);

      final jhSameFinder = find.text('JumpHost Same Group');
      final jhOtherFinder = find.text('JumpHost Other Group');
      final headerFinder = find.widgetWithText(
        SectionHeader,
        t.groups.otherGroups.toUpperCase(),
      );

      expect(jhSameFinder, findsOneWidget);
      expect(headerFinder, findsOneWidget);
      expect(jhOtherFinder, findsOneWidget);

      final sameY = tester.getTopLeft(jhSameFinder).dy;
      final headerY = tester.getTopLeft(headerFinder).dy;
      final otherY = tester.getTopLeft(jhOtherFinder).dy;

      expect(sameY, lessThan(headerY));
      expect(headerY, lessThan(otherY));

      await tester.tap(jhOtherFinder);
      await tester.pumpAndSettle();

      expect(find.text('JumpHost Other Group'), findsOneWidget);
    });

    testWidgets(
      'jump-host list with all candidates in same group draws no header',
      (tester) async {
        final currentProfile = profileFixture(
          id: 'prof-curr',
          name: 'Current Machine',
          group: 'General',
        );
        final jhSame1 = profileFixture(
          id: 'jh-1',
          name: 'JumpHost One',
          group: 'General',
          host: 'jh1.example.com',
        );
        final jhSame2 = profileFixture(
          id: 'jh-2',
          name: 'JumpHost Two',
          group: 'General',
          host: 'jh2.example.com',
        );

        await pumpProfileForm(
          tester,
          profile: currentProfile,
          profiles: [currentProfile, jhSame1, jhSame2],
        );

        await openMoreOptions(tester);
        final jumpHostTile = find.text(t.profileForm.jumpHostNone);
        await tester.scrollUntilVisible(
          jumpHostTile,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(jumpHostTile);
        await tester.pumpAndSettle();

        expect(find.text('JumpHost One'), findsOneWidget);
        expect(find.text('JumpHost Two'), findsOneWidget);
        expect(
          find.widgetWithText(
            SectionHeader,
            t.groups.otherGroups.toUpperCase(),
          ),
          findsNothing,
        );
      },
    );
  });
}

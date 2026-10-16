import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/screens/keys/key_form_screen.dart';
import 'package:termphin/widgets/groups/group_picker_field.dart';

import '../../support/fakes.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

/// The group picker's dropdown pops its own route after `onChanged` returns,
/// so pushing the group form from inside it used to land that pop on the
/// form instead, leaving a menu route blocking the stack.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  Future<(ProviderContainer, FakeSshKeyStorage, FakeGroupStorage)> pumpKeyForm(
    WidgetTester tester, {
    String? initialGroup,
    SshKey? existing,
    List<ProfileGroup> groups = const [
      ProfileGroup(name: 'General'),
      ProfileGroup(name: 'Servers', colorHex: '4DA3FF'),
      ProfileGroup(name: 'Staging', colorHex: '52C41A'),
    ],
    List<SshKey> keys = const [],
  }) async {
    final fakeKeys = FakeSshKeyStorage(keys);
    final fakeGroups = FakeGroupStorage(initialGroups: groups);
    final container = ProviderContainer.test(
      overrides: [
        sshKeyStorageProvider.overrideWithValue(fakeKeys),
        groupStorageProvider.overrideWithValue(fakeGroups),
      ],
    );

    await container.read(profileGroupsProvider.notifier).loadGroups();

    await pumpTestApp(
      tester,
      KeyFormScreen(initialGroup: initialGroup, existing: existing),
      container: container,
    );
    await tester.pumpAndSettle();

    return (container, fakeKeys, fakeGroups);
  }

  group('KeyFormScreen', () {
    testWidgets('New group opens the form and comes back with the group set', (
      tester,
    ) async {
      await pumpKeyForm(tester);

      await tester.tap(find.byType(GroupPickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.groups.newGroup).last);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('groupNameField')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('groupNameField')),
        'Bastions',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, t.common.save));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('groupNameField')), findsNothing);
      expect(find.byType(KeyFormScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GroupPickerField),
          matching: find.text('Bastions'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'creating an Ed25519 key with a chosen group persists that group',
      (tester) async {
        final (_, fakeKeys, _) = await pumpKeyForm(tester);

        final nameField = find.byKey(const ValueKey('keyNameField'));
        expect(nameField, findsOneWidget);

        final saveButton = find.widgetWithText(TextButton, t.common.save);
        expect(tester.widget<TextButton>(saveButton).onPressed, isNull);

        await tester.enterText(nameField, 'deploy-laptop');
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(saveButton).onPressed, isNotNull);

        await tester.tap(find.byType(GroupPickerField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Servers').last);
        await tester.pumpAndSettle();

        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        expect(find.text(t.keys.keyCreatedTitle), findsOneWidget);
        expect(find.text(t.keys.keyCreatedInstructions), findsOneWidget);

        await tester.tap(find.text(t.common.done));
        await tester.pumpAndSettle();

        expect(fakeKeys.generateEd25519Count, 1);
        expect(fakeKeys.keys.length, 1);
        final createdKey = fakeKeys.keys.first;
        expect(createdKey.name, 'deploy-laptop');
        expect(createdKey.group, 'Servers');
        expect(createdKey.keyType, SshKeyType.ed25519);
      },
    );

    testWidgets('initialGroup preselects the group the + was pressed on', (
      tester,
    ) async {
      await pumpKeyForm(tester, initialGroup: 'Staging');

      expect(
        find.descendant(
          of: find.byType(GroupPickerField),
          matching: find.text('Staging'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'selecting Import reveals the PEM field and hides the generate-only copy',
      (tester) async {
        await pumpKeyForm(tester);

        expect(find.byKey(const ValueKey('keyPemField')), findsNothing);
        expect(find.text(t.keys.selectPrivateKeyFile), findsNothing);

        await tester.tap(find.text(t.keys.keyTypeImport));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('keyPemField')), findsOneWidget);
        expect(find.text(t.keys.selectPrivateKeyFile), findsOneWidget);

        await tester.tap(find.text(t.keys.keyTypeEd25519));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('keyPemField')), findsNothing);
        expect(find.text(t.keys.selectPrivateKeyFile), findsNothing);
      },
    );

    testWidgets(
      'editing an existing key updates name and group with key type read-only',
      (tester) async {
        final existingKey = sshKeyFixture(
          id: 'key-123',
          name: 'Work Desktop',
          group: 'General',
          keyType: SshKeyType.ed25519,
        );

        final (_, fakeKeys, _) = await pumpKeyForm(
          tester,
          existing: existingKey,
          keys: [existingKey],
        );

        expect(find.text(t.keys.editKeyTitle), findsOneWidget);

        final nameField = find.byKey(const ValueKey('keyNameField'));
        expect(find.text('Work Desktop'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('keyTypeOption:import')),
          findsNothing,
        );
        expect(find.text(t.keys.keyTypeEd25519), findsOneWidget);

        await tester.enterText(nameField, 'Renamed Desktop');
        await tester.pumpAndSettle();

        await tester.tap(find.byType(GroupPickerField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Servers').last);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, t.common.save));
        await tester.pumpAndSettle();

        expect(fakeKeys.updateCount, 1);
        final updated = fakeKeys.keys.firstWhere((k) => k.id == 'key-123');
        expect(updated.name, 'Renamed Desktop');
        expect(updated.group, 'Servers');
      },
    );

    testWidgets('importing a key persists name, group, and pem', (
      tester,
    ) async {
      final (_, fakeKeys, _) = await pumpKeyForm(tester);

      await tester.tap(find.text(t.keys.keyTypeImport));
      await tester.pumpAndSettle();

      final nameField = find.byKey(const ValueKey('keyNameField'));
      final pemField = find.byKey(const ValueKey('keyPemField'));

      await tester.enterText(nameField, 'imported-server');
      await tester.enterText(
        pemField,
        '-----BEGIN OPENSSH PRIVATE KEY-----\ncontent\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(TextButton, t.common.save);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(fakeKeys.importCount, 1);
      expect(fakeKeys.keys.length, 1);
      expect(fakeKeys.keys.first.name, 'imported-server');
    });

    testWidgets('an encrypted key asks for its passphrase and forwards it', (
      tester,
    ) async {
      final (_, fakeKeys, _) = await pumpKeyForm(tester);

      await tester.tap(find.text(t.keys.keyTypeImport));
      await tester.pumpAndSettle();

      final passphraseField = find.byKey(const ValueKey('keyPassphraseField'));
      expect(passphraseField, findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('keyNameField')),
        'locked-server',
      );
      await tester.enterText(
        find.byKey(const ValueKey('keyPemField')),
        encryptedEd25519Pem,
      );
      await tester.pumpAndSettle();

      expect(passphraseField, findsOneWidget);

      final saveButton = find.widgetWithText(TextButton, t.common.save);
      expect(tester.widget<TextButton>(saveButton).onPressed, isNull);

      await tester.enterText(passphraseField, encryptedEd25519Passphrase);
      await tester.pumpAndSettle();

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(fakeKeys.importCount, 1);
      expect(fakeKeys.lastImportPassphrase, encryptedEd25519Passphrase);
    });

    testWidgets('an unencrypted key is never asked for a passphrase', (
      tester,
    ) async {
      await pumpKeyForm(tester);

      await tester.tap(find.text(t.keys.keyTypeImport));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('keyPemField')),
        unencryptedEd25519Pem,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('keyPassphraseField')), findsNothing);
    });
  });
}

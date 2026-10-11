import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/providers/groups_provider.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/providers/ssh_keys_provider.dart';
import 'package:termphin/screens/keys/key_manager_screen.dart';
import 'package:termphin/services/platform/local_ssh_keys.dart';

import '../../support/fakes.dart';
import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

/// Hands the screen [found] in place of what is in the machine's own folder,
/// less whatever has been imported since, as the real scan does.
class _FakeLocalKeys extends LocalSshKeys {
  _FakeLocalKeys(this.found);

  final List<LocalSshKey> found;

  @override
  Future<List<LocalSshKey>> scan({List<SshKey> imported = const []}) async => [
    for (final key in found)
      if (!imported.any((i) => i.privateKeyPem.trim() == key.pem)) key,
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
  });

  Future<FakeSshKeyStorage> pump(
    WidgetTester tester, {
    required int local,
  }) async {
    final fakeKeys = FakeSshKeyStorage(const []);
    final pems = <String>[];
    await tester.runAsync(() async {
      for (var i = 0; i < local; i++) {
        final key = await fakeKeys.generateEd25519('seed$i', group: 'General');
        pems.add(key.privateKeyPem.trim());
      }
      await fakeKeys.saveKeys([]);
    });
    final fakeProfiles = FakeProfileStorage(const []);
    final container = ProviderContainer.test(
      overrides: [
        sshKeyStorageProvider.overrideWithValue(fakeKeys),
        profileStorageProvider.overrideWithValue(fakeProfiles),
        groupStorageProvider.overrideWithValue(
          FakeGroupStorage(
            initialGroups: const [ProfileGroup(name: 'General')],
            profilesStorage: fakeProfiles,
            keysStorage: fakeKeys,
          ),
        ),
        localSshKeysProvider.overrideWithValue(
          _FakeLocalKeys([
            for (final (i, pem) in pems.indexed)
              LocalSshKey(
                name: 'id_key$i',
                displayPath: '~/.ssh/id_key$i',
                pem: pem,
                encrypted: false,
              ),
          ]),
        ),
      ],
    );
    await container.read(profileGroupsProvider.notifier).loadGroups();
    await pumpTestApp(tester, const KeyManagerScreen(), container: container);
    await tester.pumpAndSettle();
    return fakeKeys;
  }

  testWidgets('a key in ~/.ssh is listed apart and imported on one click', (
    tester,
  ) async {
    final storage = await pump(tester, local: 1);

    expect(find.text('On this computer'), findsOneWidget);
    expect(find.text('~/.ssh/id_key0'), findsOneWidget);
    expect(find.text('Import all'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('importLocalKey-id_key0')));
    await tester.pumpAndSettle();

    final keys = await storage.loadKeys();
    expect(keys.map((key) => key.name), ['id_key0']);
    expect(find.byKey(const ValueKey('localKeysSection')), findsNothing);
    expect(find.text('id_key0'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('Import all takes every key found', (tester) async {
    final storage = await pump(tester, local: 2);

    await tester.tap(find.text('Import all'));
    await tester.pumpAndSettle();

    final keys = await storage.loadKeys();
    expect(keys.map((key) => key.name), ['id_key0', 'id_key1']);
    expect(find.byKey(const ValueKey('localKeysSection')), findsNothing);
  }, variant: _desktop);

  testWidgets('a phone has no folder to look in', (tester) async {
    await pump(tester, local: 1);

    expect(find.byKey(const ValueKey('localKeysSection')), findsNothing);
  });
}

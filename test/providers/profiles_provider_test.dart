import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/services/analytics/analytics_service.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const analyticsChannel = MethodChannel('posthog_flutter');
  final captured = <Map<String, Object?>>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async {
          if (call.method == 'capture') {
            final arguments = call.arguments as Map;
            captured.add({
              'event': arguments['eventName'],
              ...?(arguments['properties'] as Map?)?.cast<String, Object?>(),
            });
          }
          return null;
        });
    AnalyticsService.instance.resetForTest();
    await AnalyticsService.instance.setConsent(true);
    captured.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
  });

  ProviderContainer createContainer(FakeProfileStorage storage) {
    return ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
  }

  test('loads profiles from storage', () async {
    final profile = profileFixture();
    final storage = FakeProfileStorage([profile]);
    final container = createContainer(storage);

    await container.read(profilesProvider.notifier).loadProfiles();

    expect(container.read(profilesProvider).single.id, profile.id);
  });

  test('adds a trimmed password profile and reloads state', () async {
    final storage = FakeProfileStorage();
    final container = createContainer(storage);
    final notifier = container.read(profilesProvider.notifier);

    await notifier.addProfile(
      name: '  Production  ',
      host: '  example.com ',
      port: 2222,
      username: ' deploy ',
      authMethod: AuthMethod.password,
      password: 'secret',
      privateKey: 'must-not-be-stored',
      passphrase: 'must-not-be-stored',
      sshKeyId: 'must-not-be-stored',
    );

    final profile = container.read(profilesProvider).single;
    expect(profile.id, isNotEmpty);
    expect(profile.name, 'Production');
    expect(profile.host, 'example.com');
    expect(profile.username, 'deploy');
    expect(profile.port, 2222);
    expect(profile.password, 'secret');
    expect(profile.privateKey, isNull);
    expect(profile.passphrase, isNull);
    expect(profile.sshKeyId, isNull);
    expect(storage.addCount, 1);
  });

  test('stores either a managed key id or an inline private key', () async {
    final storage = FakeProfileStorage();
    final container = createContainer(storage);
    final notifier = container.read(profilesProvider.notifier);

    await notifier.addProfile(
      name: 'Managed',
      host: 'managed.example.com',
      port: 22,
      username: 'user',
      authMethod: AuthMethod.privateKey,
      privateKey: 'inline-ignored',
      passphrase: 'phrase',
      sshKeyId: 'key-1',
    );
    await notifier.addProfile(
      name: 'Inline',
      host: 'inline.example.com',
      port: 22,
      username: 'user',
      authMethod: AuthMethod.privateKey,
      privateKey: 'inline-pem',
      passphrase: 'phrase',
    );

    final managed = container
        .read(profilesProvider)
        .firstWhere((profile) => profile.name == 'Managed');
    final inline = container
        .read(profilesProvider)
        .firstWhere((profile) => profile.name == 'Inline');
    expect(managed.sshKeyId, 'key-1');
    expect(managed.privateKey, isNull);
    expect(inline.sshKeyId, isNull);
    expect(inline.privateKey, 'inline-pem');
  });

  test('changing authentication method clears stale secrets', () async {
    final original = profileFixture(
      authMethod: AuthMethod.privateKey,
      password: 'stale-password',
      privateKey: 'stale-key',
      passphrase: 'stale-phrase',
      sshKeyId: 'stale-key-id',
    );
    final storage = FakeProfileStorage([original]);
    final container = createContainer(storage);

    await container
        .read(profilesProvider.notifier)
        .updateProfile(
          original,
          name: original.name,
          host: original.host,
          port: original.port,
          username: original.username,
          authMethod: AuthMethod.none,
        );

    final updated = container.read(profilesProvider).single;
    expect(updated.authMethod, AuthMethod.none);
    expect(updated.password, isNull);
    expect(updated.privateKey, isNull);
    expect(updated.passphrase, isNull);
    expect(updated.sshKeyId, isNull);
  });

  test('deletes profiles and reloads state', () async {
    final profile = profileFixture();
    final storage = FakeProfileStorage([profile]);
    final container = createContainer(storage);

    await container.read(profilesProvider.notifier).deleteProfile(profile.id);

    expect(container.read(profilesProvider), isEmpty);
    expect(storage.deleteCount, 1);
  });

  test(
    'touchLastConnected updates known profiles and ignores missing IDs',
    () async {
      final profile = profileFixture();
      final storage = FakeProfileStorage([profile]);
      final container = createContainer(storage);
      final notifier = container.read(profilesProvider.notifier);

      await notifier.touchLastConnected('missing');
      expect(storage.updateCount, 0);

      await notifier.touchLastConnected(profile.id);
      expect(storage.updateCount, 1);
      expect(
        container.read(profilesProvider).single.lastConnectedAt,
        isNotNull,
      );
    },
  );

  test('adding a profile reports the activation, without the server', () async {
    final storage = FakeProfileStorage();
    final container = createContainer(storage);

    await container
        .read(profilesProvider.notifier)
        .addProfile(
          name: 'Production',
          host: 'secret.example.com',
          port: 22,
          username: 'root',
          authMethod: AuthMethod.privateKey,
          privateKey: 'pem',
        );
    await pumpEventQueue();

    expect(captured, [
      {'event': 'profile_created', 'auth_method': 'privateKey'},
    ]);
  });

  test('a storage failure is not counted as an activation', () async {
    final storage = FakeProfileStorage()..failNextAdd = true;
    final container = createContainer(storage);

    await expectLater(
      container
          .read(profilesProvider.notifier)
          .addProfile(
            name: 'Production',
            host: 'example.com',
            port: 22,
            username: 'deploy',
            authMethod: AuthMethod.password,
            password: 'secret',
          ),
      throwsA(anything),
    );
    await pumpEventQueue();

    expect(captured, isEmpty);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/storage/profile_storage.dart';

import '../../support/fake_master_key_store.dart';
import '../../support/fixtures.dart';

Future<List<Map<String, dynamic>>> storedProfiles() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList('ssh_profiles') ?? const [])
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .toList();
}

void main() {
  late ProfileStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = ProfileStorage(cipher: cipherFixture());
  });

  test('returns an empty list when no profiles are stored', () async {
    expect(await storage.loadProfiles(), isEmpty);
  });

  test('saves and loads profiles newest first', () async {
    final older = profileFixture(id: 'older', createdAt: DateTime.utc(2025));
    final newer = profileFixture(id: 'newer', createdAt: DateTime.utc(2026));

    await storage.saveProfiles([older, newer]);

    expect((await storage.loadProfiles()).map((p) => p.id), ['newer', 'older']);
  });

  test('adds, updates, and deletes profiles', () async {
    final profile = profileFixture();
    await storage.addProfile(profile);

    await storage.updateProfile(profile.copyWith(name: 'Renamed'));
    expect((await storage.loadProfiles()).single.name, 'Renamed');

    await storage.deleteProfile(profile.id);
    expect(await storage.loadProfiles(), isEmpty);
  });

  test('throws when updating a missing profile', () async {
    expect(
      () => storage.updateProfile(profileFixture()),
      throwsA(isA<StateError>()),
    );
  });

  test('skips a corrupted entry without losing valid profiles', () async {
    final valid = profileFixture();
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': ['not-json', valid.encode()],
    });

    final profiles = await storage.loadProfiles();

    expect(profiles.map((profile) => profile.id), [valid.id]);
  });

  test('credentials never reach SharedPreferences in the clear', () async {
    await storage.saveProfiles([
      profileFixture(password: 'hunter2', passphrase: 'correct-horse'),
    ]);

    final raw = (await storedProfiles()).single;
    expect(raw['password'], startsWith('enc:v1:'));
    expect(raw['passphrase'], startsWith('enc:v1:'));
    expect(jsonEncode(raw), isNot(contains('hunter2')));
    expect(jsonEncode(raw), isNot(contains('correct-horse')));
    expect(raw['host'], 'example.com');
    expect(raw['username'], 'deploy');
  });

  test('round-trips credentials', () async {
    await storage.saveProfiles([
      profileFixture(password: 'hunter2', passphrase: 'correct-horse'),
    ]);

    final loaded = (await storage.loadProfiles()).single;
    expect(loaded.password, 'hunter2');
    expect(loaded.passphrase, 'correct-horse');
  });

  test('profiles written before encryption are read, then resealed', () async {
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': [profileFixture(password: 'hunter2').encode()],
    });

    expect((await storage.loadProfiles()).single.password, 'hunter2');

    expect((await storedProfiles()).single['password'], startsWith('enc:v1:'));
    expect((await storage.loadProfiles()).single.password, 'hunter2');
  });

  test('a lost master key drops the secret but keeps the profile', () async {
    await storage.saveProfiles([profileFixture(password: 'hunter2')]);

    final replaced = ProfileStorage(cipher: cipherFixture(seed: 2));
    final loaded = (await replaced.loadProfiles()).single;

    expect(loaded.password, isNull);
    expect(loaded.host, 'example.com');
    expect(loaded.name, 'Production');
  });
}

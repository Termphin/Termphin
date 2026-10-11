@Tags(['security'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/backup/export_service.dart';
import 'package:termphin/services/storage/profile_storage.dart';
import 'package:termphin/services/storage/ssh_key_storage.dart';

import '../support/fixtures.dart';
import '../support/secure_storage_channel.dart';

/// Credentials never reach disk readable. Everything the app persists goes
/// through SharedPreferences, so the whole store is searched, not the keys the
/// storage classes are known to use - a new setting that writes a secret
/// without sealing it is exactly what this is here to catch.
///
/// The canaries carry a `!`, which base64 never produces, so a sealed value
/// cannot contain one by chance.
const _password = 'canary!password';
const _inlineKey = 'canary!inline-private-key';
const _passphrase = 'canary!passphrase';
const _managedKey = 'canary!managed-private-key';
const _canaries = [_password, _inlineKey, _passphrase, _managedKey];

Future<String> _everythingOnDisk() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  return [
    for (final key in preferences.getKeys()) '$key=${preferences.get(key)}',
  ].join('\n');
}

void _expectNoCanary(String haystack) {
  for (final canary in _canaries) {
    expect(haystack, isNot(contains(canary)), reason: '$canary leaked');
  }
}

Future<void> _storeEverySecret() async {
  await ProfileStorage().saveProfiles([
    profileFixture(id: 'password-profile', password: _password),
    profileFixture(
      id: 'key-profile',
      authMethod: AuthMethod.privateKey,
      password: null,
      privateKey: _inlineKey,
      passphrase: _passphrase,
    ),
  ]);
  await SshKeyStorage().saveKeys([sshKeyFixture(privateKeyPem: _managedKey)]);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  test('saved profiles and keys hold no credential in the clear', () async {
    await _storeEverySecret();

    _expectNoCanary(await _everythingOnDisk());
    final profiles = await ProfileStorage().loadProfiles();
    expect(profiles.map((p) => p.password), contains(_password));
    final keys = await SshKeyStorage().loadKeys();
    expect(keys.single.privateKeyPem, _managedKey);
  });

  test('a record written before encryption is sealed once read', () async {
    final legacy = profileFixture(id: 'legacy', password: _password).toJson();
    SharedPreferences.setMockInitialValues({
      'ssh_profiles': [jsonEncode(legacy)],
    });

    final profiles = await ProfileStorage().loadProfiles();

    expect(profiles.single.password, _password);
    _expectNoCanary(await _everythingOnDisk());
  });

  test('an encrypted backup of everything holds no credential', () async {
    await _storeEverySecret();

    final backup = await ExportService().exportToJson(
      const ExportOptions(
        includePasswords: true,
        includeInlinePrivateKeys: true,
        includeKnownHosts: true,
      ),
      passphrase: 'correct horse battery',
    );

    _expectNoCanary(backup);
  });

  test('a backup without secrets holds none', () async {
    await _storeEverySecret();

    final backup = await ExportService().exportToJson(
      const ExportOptions(includeSshKeys: false),
    );

    _expectNoCanary(backup);
  });
}

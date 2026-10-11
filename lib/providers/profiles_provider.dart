import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/port_forwarding_rule.dart';
import '../models/ssh_profile.dart';
import '../services/analytics/analytics_service.dart';
import '../services/storage/group_storage.dart';
import '../services/storage/profile_storage.dart';

final profileStorageProvider = Provider<ProfileStorage>((ref) {
  return ProfileStorage();
});

final profilesProvider = NotifierProvider<ProfilesNotifier, List<SshProfile>>(
  ProfilesNotifier.new,
);

class ProfilesNotifier extends Notifier<List<SshProfile>> {
  late final ProfileStorage _storage;
  static const Uuid _uuid = Uuid();

  @override
  List<SshProfile> build() {
    _storage = ref.read(profileStorageProvider);
    loadProfiles();
    return const [];
  }

  Future<void> loadProfiles() async {
    final profiles = await _storage.loadProfiles();
    if (!ref.mounted) return;
    state = profiles;
  }

  /// Reports the creation event before the reload, so a storage failure
  /// above cannot be counted as an activation.
  Future<void> addProfile({
    required String name,
    required String host,
    required int port,
    required String username,
    required AuthMethod authMethod,
    String? password,
    String? privateKey,
    String? passphrase,
    String? sshKeyId,
    List<PortForwardingRule>? portForwardings,
    String group = GroupStorage.defaultGroup,
    String? iconName,
    String? colorHex,
    List<String>? fallbackHosts,
    bool? mainHostFirst,
    String? jumpHostProfileId,
  }) async {
    final profile = SshProfile(
      id: _uuid.v4(),
      name: name.trim(),
      host: host.trim(),
      port: port,
      username: username.trim(),
      authMethod: authMethod,
      password: authMethod == AuthMethod.password ? password : null,
      privateKey: (authMethod == AuthMethod.privateKey && sshKeyId == null)
          ? privateKey
          : null,
      passphrase: authMethod == AuthMethod.privateKey ? passphrase : null,
      sshKeyId: authMethod == AuthMethod.privateKey ? sshKeyId : null,
      createdAt: DateTime.now(),
      portForwardings: portForwardings ?? [],
      group: group,
      iconName: iconName,
      colorHex: colorHex,
      fallbackHosts: fallbackHosts ?? [],
      mainHostFirst: mainHostFirst ?? true,
      jumpHostProfileId: jumpHostProfileId,
    );

    await _storage.addProfile(profile);
    unawaited(
      AnalyticsService.instance.capture(
        AnalyticsEvent.profileCreated,
        properties: {AnalyticsProperty.authMethod: profile.authMethod.name},
      ),
    );
    await loadProfiles();
  }

  Future<void> updateProfile(
    SshProfile existingProfile, {
    required String name,
    required String host,
    required int port,
    required String username,
    required AuthMethod authMethod,
    String? password,
    String? privateKey,
    String? passphrase,
    String? sshKeyId,
    List<PortForwardingRule>? portForwardings,
    String? group,
    String? iconName,
    String? colorHex,
    List<String>? fallbackHosts,
    bool? mainHostFirst,
    String? jumpHostProfileId,
  }) async {
    final updated = existingProfile.copyWith(
      name: name.trim(),
      host: host.trim(),
      port: port,
      username: username.trim(),
      authMethod: authMethod,
      password: authMethod == AuthMethod.password ? password : null,
      privateKey: (authMethod == AuthMethod.privateKey && sshKeyId == null)
          ? privateKey
          : null,
      passphrase: authMethod == AuthMethod.privateKey ? passphrase : null,
      sshKeyId: authMethod == AuthMethod.privateKey ? sshKeyId : null,
      clearSshKeyId: authMethod != AuthMethod.privateKey || sshKeyId == null,
      clearPrivateKey: authMethod != AuthMethod.privateKey || sshKeyId != null,
      clearPassword: authMethod != AuthMethod.password,
      clearPassphrase: authMethod != AuthMethod.privateKey,
      updatedAt: DateTime.now(),
      portForwardings: portForwardings,
      group: group,
      iconName: iconName,
      colorHex: colorHex,
      fallbackHosts: fallbackHosts,
      mainHostFirst: mainHostFirst,
      jumpHostProfileId: jumpHostProfileId,
      clearJumpHost: jumpHostProfileId == null,
    );

    await _storage.updateProfile(updated);
    await loadProfiles();
  }

  Future<void> deleteProfile(String id) async {
    await _storage.deleteProfile(id);
    await loadProfiles();
  }

  Future<void> touchLastConnected(String id) async {
    final profiles = await _storage.loadProfiles();
    final index = profiles.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final updated = profiles[index].copyWith(lastConnectedAt: DateTime.now());
    await _storage.updateProfile(updated);
    await loadProfiles();
  }

  /// Records which of [SshProfile.connectionCandidates] actually answered,
  /// so the next connection attempt tries it first instead of failing
  /// against dead addresses ahead of it in the queue every time.
  Future<void> updateLastGoodHost(String id, String host) async {
    final profiles = await _storage.loadProfiles();
    final index = profiles.indexWhere((p) => p.id == id);
    if (index == -1 || profiles[index].lastGoodHost == host) return;
    final updated = profiles[index].copyWith(lastGoodHost: host);
    await _storage.updateProfile(updated);
    await loadProfiles();
  }
}

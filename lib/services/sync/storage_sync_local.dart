import 'package:clock/clock.dart';

import '../../models/known_host.dart';
import '../../models/profile_group.dart';
import '../../models/snippet.dart';
import '../../models/ssh_key.dart';
import '../../models/ssh_profile.dart';
import '../storage/group_storage.dart';
import '../storage/known_hosts_store.dart';
import '../storage/profile_storage.dart';
import '../storage/snippet_storage.dart';
import '../storage/ssh_key_storage.dart';
import 'sync_engine.dart';

/// Kinds of record synced, as named in the payload.
abstract final class SyncKind {
  static const profile = 'profile';
  static const key = 'key';
  static const snippet = 'snippet';
  static const groups = 'groups';
  static const knownHost = 'knownHost';
}

/// This device's machines, keys, snippets, groups and pinned host keys, as
/// [SyncRecord]s.
///
/// A record carries what the device itself stores - a machine with its
/// password and inline key, a key with its private half. That is safe to
/// hand over only because the engine seals every record before it leaves.
///
/// The group list is one record: groups are keyed by name and ordered, and
/// a list merged entry by entry would lose the order. Pinned host keys have
/// no timestamp of their own, so theirs is the time they were pinned.
class StorageSyncLocal implements SyncLocal {
  StorageSyncLocal({
    ProfileStorage? profiles,
    SshKeyStorage? keys,
    SnippetStorage? snippets,
    GroupStorage? groups,
    KnownHostsStore? knownHosts,
  }) : _profiles = profiles ?? ProfileStorage(),
       _keys = keys ?? SshKeyStorage(),
       _snippets = snippets ?? SnippetStorage(),
       _groups = groups ?? GroupStorage(),
       _knownHosts = knownHosts ?? KnownHostsStore.instance;

  final ProfileStorage _profiles;
  final SshKeyStorage _keys;
  final SnippetStorage _snippets;
  final GroupStorage _groups;
  final KnownHostsStore _knownHosts;

  /// The id of the one group-list record.
  static const groupsId = 'all';

  /// When the group list last changed here, for settling a conflict with
  /// another device's list. Groups carry no time of their own.
  DateTime groupsChangedAt = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  @override
  Future<List<SyncRecord>> readAll() async {
    final groups = await _groups.loadGroups();
    return [
      for (final profile in await _profiles.loadProfiles())
        SyncRecord(
          kind: SyncKind.profile,
          id: profile.id,
          data: profile.toJson(),
          updatedAt: profile.updatedAt,
        ),
      for (final key in await _keys.loadKeys())
        SyncRecord(
          kind: SyncKind.key,
          id: key.id,
          data: key.toJson(),
          updatedAt: key.updatedAt,
        ),
      for (final snippet in await _snippets.loadSnippets())
        SyncRecord(
          kind: SyncKind.snippet,
          id: snippet.id,
          data: snippet.toJson(),
          updatedAt: snippet.updatedAt,
        ),
      SyncRecord(
        kind: SyncKind.groups,
        id: groupsId,
        data: {
          'groups': [for (final group in groups) group.toJson()],
        },
        updatedAt: groupsChangedAt,
      ),
      for (final host in await _knownHosts.entries())
        SyncRecord(
          kind: SyncKind.knownHost,
          id: host.slot,
          data: host.toJson(),
          updatedAt: host.addedAt,
        ),
    ];
  }

  @override
  Future<void> upsert(SyncRecord record) async {
    switch (record.kind) {
      case SyncKind.profile:
        final profile = SshProfile.fromJson(record.data);
        if (await _profiles.getProfile(profile.id) == null) {
          await _profiles.addProfile(profile);
        } else {
          await _profiles.updateProfile(profile);
        }
      case SyncKind.key:
        final key = SshKey.fromJson(record.data);
        final keys = await _keys.loadKeys();
        final index = keys.indexWhere((existing) => existing.id == key.id);
        if (index == -1) {
          keys.add(key);
        } else {
          keys[index] = key;
        }
        await _keys.saveKeys(keys);
      case SyncKind.snippet:
        final snippet = Snippet.fromJson(record.data);
        final snippets = await _snippets.loadSnippets();
        if (snippets.any((existing) => existing.id == snippet.id)) {
          await _snippets.updateSnippet(snippet);
        } else {
          await _snippets.addSnippet(snippet);
        }
      case SyncKind.groups:
        final list = record.data['groups'];
        if (list is! List) return;
        await _groups.saveGroups([
          for (final item in list)
            if (item is Map)
              ProfileGroup.fromJson(item.cast<String, dynamic>()),
        ]);
        groupsChangedAt = clock.now().toUtc();
      case SyncKind.knownHost:
        await _knownHosts.trust(KnownHost.fromJson(record.data));
    }
  }

  @override
  Future<void> delete(String kind, String id) async {
    switch (kind) {
      case SyncKind.profile:
        await _profiles.deleteProfile(id);
      case SyncKind.key:
        await _keys.deleteKey(id);
      case SyncKind.snippet:
        await _snippets.deleteSnippet(id);
      case SyncKind.knownHost:
        await _knownHosts.forgetSlot(id);
      case SyncKind.groups:
        return;
    }
  }
}

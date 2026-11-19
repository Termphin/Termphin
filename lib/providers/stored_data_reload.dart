import 'package:flutter_riverpod/misc.dart';

import 'groups_provider.dart';
import 'profiles_provider.dart';
import 'snippets_provider.dart';
import 'ssh_keys_provider.dart';

/// Reads everything the app keeps back from storage, after something wrote
/// it from outside the screens that own it - a backup import, a sync.
///
/// Keys have no notifier of their own, only a revision the key manager
/// reloads on; a path that forgot to bump it left the manager showing the
/// keys from before, which a desktop's sections, kept alive beside each
/// other, made plain after every import.
Future<void> reloadStoredData(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  await read<ProfileGroupsNotifier>(
    profileGroupsProvider.notifier,
  ).loadGroups();
  await read<ProfilesNotifier>(profilesProvider.notifier).loadProfiles();
  await read<SnippetsNotifier>(snippetsProvider.notifier).loadSnippets();
  read<SshKeysRevision>(sshKeysRevisionProvider.notifier).bump();
}

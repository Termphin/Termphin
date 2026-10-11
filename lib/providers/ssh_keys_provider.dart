import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage/ssh_key_storage.dart';

/// Keys have no notifier - the key manager owns its own list and reloads it.
/// This exists so everything that reassigns a key's group goes through one
/// store, and so a test can hand that store a fake.
final sshKeyStorageProvider = Provider<SshKeyStorage>((ref) {
  return SshKeyStorage();
});

/// Bumped by whatever edits a key outside the key manager (the search screen),
/// so the manager's own list, which it loads itself, reloads.
final sshKeysRevisionProvider = NotifierProvider<SshKeysRevision, int>(
  SshKeysRevision.new,
);

class SshKeysRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

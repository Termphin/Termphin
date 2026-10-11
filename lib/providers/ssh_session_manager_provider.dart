import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh/ssh_session_manager.dart';

/// Indirection so tests can supply their own manager.
final sshSessionManagerProvider = Provider<SshSessionManager>((ref) {
  return SshSessionManager.instance;
});

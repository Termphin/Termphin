import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sftp/transfer_queue.dart';

/// The transfer queue of one session, keyed by session id.
///
/// Held for as long as the session's view watches it; closing the tab drops
/// the view, and disposing the queue cancels whatever it still had to do.
final transferQueueProvider = Provider.autoDispose
    .family<TransferQueue, String>((ref, sessionId) {
      final queue = TransferQueue();
      ref.onDispose(queue.dispose);
      return queue;
    });

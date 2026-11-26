import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/push/push_service.dart';
import 'account_provider.dart';

/// The relay keys of the signed-in account: which machines are set up for
/// notifications and live status. Empty while signed out.
final relayKeysProvider = StreamProvider<List<RelayServer>>((ref) {
  if (ref.watch(accountProvider) == null) return Stream.value(const []);
  return PushService.instance.servers();
});

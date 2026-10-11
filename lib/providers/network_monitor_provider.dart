import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh/network_monitor.dart';

final networkMonitorProvider = Provider<NetworkMonitor>((ref) {
  return NetworkMonitor.instance;
});

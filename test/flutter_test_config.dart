import 'dart:async';

import 'package:termphin/services/analytics/analytics_config.dart';

/// Runs before every test file. Release builds get the analytics key at
/// build time and tests run without one, so a stand-in key keeps the
/// analytics paths under test as they are in a shipped build.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AnalyticsConfig.apiKeyOverride = 'phc_test';
  await testMain();
}

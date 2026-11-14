import 'dart:async';

import 'package:termphin/services/analytics/analytics_service.dart';

import 'support/analytics_recorder.dart';

/// Runs before every test file. A release build carries a Firebase project
/// and tests run without one, so a recorder stands in for it and keeps the
/// analytics paths under test as they are in a shipped build.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AnalyticsService.backendOverride = () => analyticsRecorder;
  await testMain();
}

import 'package:flutter/foundation.dart';

/// Configuration for the PostHog analytics backend.
///
/// The project key is passed in at build time (`--dart-define=POSTHOG_API_KEY`,
/// see `scripts/build_release.sh`) rather than written here, so a build from
/// source - a fork, a contributor's debug run - sends nothing to the
/// project's analytics. Without it, analytics is simply off.
class AnalyticsConfig {
  const AnalyticsConfig._();

  static const _builtInApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: '',
  );

  /// Stands in for the build-time key in tests, which run without one.
  @visibleForTesting
  static String? apiKeyOverride;

  static String get projectApiKey => apiKeyOverride ?? _builtInApiKey;

  static const host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  static bool get isConfigured => projectApiKey.isNotEmpty;
}

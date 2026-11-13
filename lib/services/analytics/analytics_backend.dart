import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Where analytics events and crash reports go, so the consent rules in
/// `AnalyticsService` do not depend on any one SDK and tests can watch what
/// would have left the device.
abstract interface class AnalyticsBackend {
  /// Turns collection on or off for good, across launches. Off also drops
  /// the crash reports kept on the device since collection last ran.
  Future<void> setCollectionEnabled(bool enabled);

  Future<void> logEvent(String name, Map<String, Object> parameters);

  Future<void> recordError(Object error, StackTrace? stack, {bool fatal});
}

/// Google Analytics and Crashlytics, both from the Firebase project.
///
/// Consent mode grants analytics storage only: no advertising id is read
/// (switched off in the manifest and `Info.plist` as well), and nothing is
/// shared for ads.
class FirebaseAnalyticsBackend implements AnalyticsBackend {
  FirebaseAnalyticsBackend();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    await _analytics.setConsent(
      analyticsStorageConsentGranted: enabled,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await _analytics.setAnalyticsCollectionEnabled(enabled);
    await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
    if (!enabled) await _crashlytics.deleteUnsentReports();
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) =>
      _analytics.logEvent(name: name, parameters: parameters);

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) => _crashlytics.recordError(error, stack, fatal: fatal);
}

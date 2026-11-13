import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Where the app's Firebase project is, read at build time.
///
/// The values come in as `--dart-define`s (`--dart-define-from-file` with the
/// project's `firebase.json`, which `scripts/build_release.sh` passes when it
/// finds one) rather than written here, so a build from source - a fork, a
/// contributor's debug run - talks to no Firebase project at all. Without
/// them [options] is null and the app runs without Firebase: no crash
/// reports, no analytics, no account, no push.
class FirebaseConfig {
  const FirebaseConfig._();

  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _androidDebugAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_DEBUG_APP_ID',
  );
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  /// Stands in for the build-time values in tests.
  @visibleForTesting
  static FirebaseOptions? Function()? optionsOverride;

  /// The options for this platform and build, or null where there are none:
  /// no config was built in, or the platform has no app in the project
  /// (Firebase has no Linux or Windows SDK). A debug build on Android is an
  /// app of its own, `dev.termphin.termphin.debug`.
  static FirebaseOptions? get options {
    final override = optionsOverride;
    if (override != null) return override();
    return optionsFor(defaultTargetPlatform, debug: kDebugMode);
  }

  @visibleForTesting
  static FirebaseOptions? optionsFor(
    TargetPlatform platform, {
    required bool debug,
  }) {
    if (kIsWeb || _projectId.isEmpty || _senderId.isEmpty) return null;
    return switch (platform) {
      TargetPlatform.android when _androidApiKey.isNotEmpty => FirebaseOptions(
        apiKey: _androidApiKey,
        appId: debug && _androidDebugAppId.isNotEmpty
            ? _androidDebugAppId
            : _androidAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _storageBucket,
      ),
      TargetPlatform.iOS when _iosApiKey.isNotEmpty => const FirebaseOptions(
        apiKey: _iosApiKey,
        appId: _iosAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _storageBucket,
        iosBundleId: _iosBundleId,
      ),
      _ => null,
    };
  }
}

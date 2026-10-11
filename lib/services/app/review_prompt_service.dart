import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';

const kReviewSuccessfulConnectionsPrefsKey = 'review_successful_connections';
const kReviewFirstConnectionAtPrefsKey = 'review_first_connection_at';
const kReviewLastPromptedVersionPrefsKey = 'review_last_prompted_version';
const kReviewPromptedAtPrefsKey = 'review_prompted_at';

/// Enough sessions that the app has demonstrably worked for this user.
const _minSuccessfulConnections = 5;

/// Long enough that the first evening of setting profiles up is over.
const _minDaysSinceFirstConnection = 3;

/// Play throttles the dialog itself, but it never says whether it showed one,
/// so a second ask is only worth making after a long gap and a new release.
const _repromptCooldownDays = 120;

/// The Play In-App Review API, behind an interface so tests can drive it.
abstract class ReviewLauncher {
  bool get canOpenStoreListing;

  Future<bool> isAvailable();

  /// Asks Play to show its review dialog. Play decides whether it actually
  /// appears and never reports back either way.
  Future<void> requestReview();

  Future<void> openStoreListing();
}

class _PlayReviewLauncher implements ReviewLauncher {
  const _PlayReviewLauncher();

  static const kAppStoreId = String.fromEnvironment(
    'APP_STORE_ID',
    defaultValue: '',
  );

  @override
  bool get canOpenStoreListing {
    if (isAndroidPlatform) return true;
    if (isIOSPlatform) return kAppStoreId.isNotEmpty;
    return false;
  }

  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();

  @override
  Future<void> openStoreListing() async {
    if (isIOSPlatform) {
      if (kAppStoreId.isNotEmpty) {
        await InAppReview.instance.openStoreListing(appStoreId: kAppStoreId);
      } else {
        throw Exception('App Store ID not configured');
      }
    } else {
      await InAppReview.instance.openStoreListing();
    }
  }
}

/// Decides when to ask for a Play Store review.
///
/// Play's own dialog is the only thing shown - there is deliberately no "do
/// you like Termphin?" question in front of it. Filtering who gets asked by
/// how they feel is against Play policy, and the API gives no result to act
/// on anyway.
///
/// Everything here is device-local: a counter of successful connections, when
/// the first one happened, and what was asked when. Nothing about it is sent
/// anywhere beyond the `review_prompt_requested` analytics event.
class ReviewPromptService {
  ReviewPromptService._({ReviewLauncher? launcher, DateTime Function()? now})
    : _launcher = launcher ?? const _PlayReviewLauncher(),
      _now = now ?? DateTime.now;

  @visibleForTesting
  factory ReviewPromptService.forTesting({
    required ReviewLauncher launcher,
    DateTime Function()? now,
  }) => ReviewPromptService._(launcher: launcher, now: now);

  static final ReviewPromptService instance = ReviewPromptService._();

  final ReviewLauncher _launcher;
  final DateTime Function() _now;

  /// Counts one connection, seeding the clock on the first. Called for every
  /// successful connect, so it stays cheap and never touches the launcher.
  Future<void> recordSuccessfulConnection() async {
    final preferences = await SharedPreferences.getInstance();
    final count =
        (preferences.getInt(kReviewSuccessfulConnectionsPrefsKey) ?? 0) + 1;
    await preferences.setInt(kReviewSuccessfulConnectionsPrefsKey, count);
    if (preferences.getInt(kReviewFirstConnectionAtPrefsKey) == null) {
      await preferences.setInt(
        kReviewFirstConnectionAtPrefsKey,
        _now().millisecondsSinceEpoch,
      );
    }
  }

  /// Requests the review dialog if every gate passes. Returns whether the
  /// request was made - not whether Play showed anything, which is unknowable.
  /// A failed request burns no cooldown, so it is tried again next time.
  Future<bool> maybePrompt(String currentVersion) async {
    final preferences = await SharedPreferences.getInstance();
    if (!_gatesPass(preferences, currentVersion)) return false;
    if (!await _launcher.isAvailable()) return false;
    try {
      await _launcher.requestReview();
    } catch (_) {
      return false;
    }
    await preferences.setString(
      kReviewLastPromptedVersionPrefsKey,
      currentVersion,
    );
    await preferences.setInt(
      kReviewPromptedAtPrefsKey,
      _now().millisecondsSinceEpoch,
    );
    return true;
  }

  /// The Settings row: always available, independent of Play's quota.
  Future<void> openStoreListing() => _launcher.openStoreListing();

  bool get canOpenStoreListing => _launcher.canOpenStoreListing;

  bool _gatesPass(SharedPreferences preferences, String currentVersion) {
    final count = preferences.getInt(kReviewSuccessfulConnectionsPrefsKey) ?? 0;
    if (count < _minSuccessfulConnections) return false;

    final firstAt = preferences.getInt(kReviewFirstConnectionAtPrefsKey);
    if (firstAt == null) return false;
    final since = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(firstAt),
    );
    if (since.inDays < _minDaysSinceFirstConnection) return false;

    final promptedAt = preferences.getInt(kReviewPromptedAtPrefsKey);
    if (promptedAt == null) return true;
    final sincePrompt = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(promptedAt),
    );
    if (sincePrompt.inDays < _repromptCooldownDays) return false;
    return preferences.getString(kReviewLastPromptedVersionPrefsKey) !=
        currentVersion;
  }
}

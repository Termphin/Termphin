import 'package:shared_preferences/shared_preferences.dart';

import 'legal_updates_service.dart';

const kOnboardingCompletedPrefsKey = 'onboarding_completed';

/// Whether the first-launch onboarding flow has been shown and finished.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  Future<bool> isCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kOnboardingCompletedPrefsKey) ?? false;
  }

  /// Finishing onboarding, where the terms and the privacy policy are
  /// linked under the consent question, also counts as having seen every
  /// change to them so far.
  Future<void> markCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(kOnboardingCompletedPrefsKey, true);
    await LegalUpdatesService.instance.markSeen();
  }
}

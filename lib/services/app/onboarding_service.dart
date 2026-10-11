import 'package:shared_preferences/shared_preferences.dart';

const kOnboardingCompletedPrefsKey = 'onboarding_completed';

/// Whether the first-launch onboarding flow has been shown and finished.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  Future<bool> isCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kOnboardingCompletedPrefsKey) ?? false;
  }

  Future<void> markCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(kOnboardingCompletedPrefsKey, true);
  }
}

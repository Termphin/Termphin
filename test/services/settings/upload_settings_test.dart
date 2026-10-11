import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/services/app/onboarding_service.dart';
import 'package:termphin/services/settings/upload_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('destination defaults to asking', () async {
    expect(await uploadDestinationSetting.load(), UploadDestination.ask);
  });

  test('destination round-trips through storage', () async {
    await uploadDestinationSetting.set(UploadDestination.currentDirectory);
    expect(
      await uploadDestinationSetting.load(),
      UploadDestination.currentDirectory,
    );

    await uploadDestinationSetting.set(UploadDestination.tmp);
    expect(await uploadDestinationSetting.load(), UploadDestination.tmp);
  });

  test(
    'an unrecognised stored destination falls back to the default',
    () async {
      SharedPreferences.setMockInitialValues({
        kUploadDestinationPrefsKey: 'somewhere-else',
      });
      expect(await uploadDestinationSetting.load(), UploadDestination.ask);
    },
  );

  group('pinLegacyUploadDestination', () {
    test('keeps tmp for an existing user who never picked', () async {
      SharedPreferences.setMockInitialValues({
        kOnboardingCompletedPrefsKey: true,
      });
      await pinLegacyUploadDestination();
      expect(await uploadDestinationSetting.load(), UploadDestination.tmp);
    });

    test(
      'keeps the current directory for a user who started after 2026-09-30',
      () async {
        SharedPreferences.setMockInitialValues({
          kOnboardingCompletedPrefsKey: true,
          kUploadDestinationLegacyPinnedPrefsKey: true,
        });
        await pinLegacyUploadDestination();
        expect(
          await uploadDestinationSetting.load(),
          UploadDestination.currentDirectory,
        );
      },
    );

    test('leaves an existing user\'s own choice alone', () async {
      SharedPreferences.setMockInitialValues({
        kOnboardingCompletedPrefsKey: true,
        kUploadDestinationPrefsKey: UploadDestination.currentDirectory.name,
      });
      await pinLegacyUploadDestination();
      expect(
        await uploadDestinationSetting.load(),
        UploadDestination.currentDirectory,
      );
    });

    test(
      'gives a fresh install the new default, also after onboarding',
      () async {
        await pinLegacyUploadDestination();
        await OnboardingService.instance.markCompleted();
        await pinLegacyUploadDestination();
        expect(await uploadDestinationSetting.load(), UploadDestination.ask);
      },
    );
  });
}

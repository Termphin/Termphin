import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The policy describes analytics by category and points at the source file
/// that holds the closed list of events and fields, so the list is never
/// copied by hand. That pointer has to keep naming a file that exists.
void main() {
  final policy = File('docs/legal/privacy-policy.md').readAsStringSync();

  test('the policy points at the file that lists every event', () {
    const source = 'lib/services/analytics/analytics_service.dart';
    expect(policy, contains('blob/main/$source'));
    expect(File(source).existsSync(), isTrue);
    expect(
      File(source).readAsStringSync(),
      allOf(contains('enum AnalyticsEvent'), contains('enum AnalyticsProperty')),
    );
  });

  test('the policy names every provider the app sends data to', () {
    for (final provider in [
      'Firebase Authentication',
      'Cloud Firestore',
      'Cloud Messaging',
      'Google Analytics for Firebase',
      'Firebase Crashlytics',
      'RevenueCat',
      'Hetzner',
    ]) {
      expect(policy, contains(provider), reason: provider);
    }
  });
}

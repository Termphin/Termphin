import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/analytics/analytics_service.dart';

/// The policy's §4 tables are the published list of what analytics sends,
/// and they are written by hand from the two closed enums. A name added to
/// either without a row in the policy makes the policy wrong.
void main() {
  final policy = File('docs/legal/privacy-policy.md').readAsStringSync();

  test('every event is listed in the privacy policy', () {
    final missing = [
      for (final event in AnalyticsEvent.values)
        if (!policy.contains('| `${event.eventName}` |')) event.eventName,
    ];
    expect(missing, isEmpty, reason: 'add these to §4 of the policy');
  });

  test('every property is listed in the privacy policy', () {
    final missing = [
      for (final property in AnalyticsProperty.values)
        if (!policy.contains('| `${property.propertyName}` |'))
          property.propertyName,
    ];
    expect(missing, isEmpty, reason: 'add these to §4 of the policy');
  });
}

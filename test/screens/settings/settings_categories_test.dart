import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/settings_categories.dart';

/// A desktop has no key toolbar and no action dock, so the Terminal row must
/// not promise them there.
void main() {
  final t = AppLocale.en.buildSync();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the Terminal row names what a desktop has', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final subtitle = SettingsCategory.terminal.subtitle(t);
    expect(subtitle, isNot(contains('toolbar')));
    expect(subtitle, isNot(contains('dock')));
  });

  test('a phone still hears about the toolbar and the dock', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SettingsCategory.terminal.subtitle(t), contains('toolbar'));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/app/project_urls.dart';
import 'package:termphin/widgets/settings/open_source_settings_section.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  late List<String> launched;

  setUp(() {
    launched = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          if (call.method == 'launch') {
            launched.add((call.arguments as Map)['url'] as String);
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, null);
  });

  for (final (title, url) in [
    (t.settings.starOnGitHub, ProjectUrls.repository),
    (t.settings.issueTracker, ProjectUrls.issues),
    (t.settings.contribute, ProjectUrls.contributing),
    (t.settings.sourceLicense, ProjectUrls.license),
  ]) {
    testWidgets('"$title" opens $url', (tester) async {
      await pumpTestApp(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: OpenSourceSettingsSection()),
        ),
      );

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      expect(launched, [url]);
    });
  }
}

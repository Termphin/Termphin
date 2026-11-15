import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/settings/app_settings.dart';
import 'package:termphin/widgets/settings/analytics_settings_section.dart';
import 'package:termphin/widgets/settings/connection_settings_section.dart';
import 'package:termphin/widgets/settings/security_settings_section.dart';
import 'package:termphin/widgets/settings/sftp_settings_section.dart';

import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
    await loadAppSettings();
  });

  final sections = <String, Widget>{
    'connection': const ConnectionSettingsSection(),
    'security': const SecuritySettingsSection(),
    'analytics': const AnalyticsSettingsSection(),
    'files': const SftpSettingsSection(),
  };

  for (final MapEntry(key: name, value: section) in sections.entries) {
    testWidgets('$name takes its full height before the system answers, so '
        'nothing below it moves when it does', (tester) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [section, const SizedBox(key: Key('below'))],
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.byKey(const Key('below'))).dy;

      for (var i = 0; i < 5; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.byKey(const Key('below'))).dy;

      expect(before, greaterThan(0));
      expect(after, before);
    });
  }
}

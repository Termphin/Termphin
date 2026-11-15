import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/settings_screen.dart';
import 'package:termphin/screens/settings/settings_search.dart';
import 'package:termphin/services/settings/app_settings.dart';

import '../../support/secure_storage_channel.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    mockSecureStorage();
    PackageInfo.setMockInitialValues(
      appName: 'Termphin',
      packageName: 'termphin',
      version: '1.4.2',
      buildNumber: '57',
      buildSignature: '',
    );
    await loadAppSettings();
  });

  /// Lets the platform answer what the screens ask it, which only happens
  /// on the real event loop.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await pumpTestApp(tester, const SettingsScreen());
    await settle(tester);
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  group('matching', () {
    const entry = SettingsSearchEntry(
      title: 'PIN lock',
      place: 'Privacy & security',
      keywords: 'password passcode',
    );

    test('ignores case', () => expect(entry.matches('pin'), isTrue));

    test('takes the words in any order', () {
      expect(entry.matches('security lock'), isTrue);
    });

    test('finds it by a word it is not called', () {
      expect(entry.matches('Password'), isTrue);
    });

    test('needs every word', () {
      expect(entry.matches('pin font'), isFalse);
    });
  });

  testWidgets('typing turns the categories into what matches', (tester) async {
    await search(tester, 'pin');

    expect(find.text(t.settings.pinLock), findsOneWidget);
    expect(find.text(t.settings.privacySecurity), findsWidgets);
    expect(find.text(t.settings.filesRow), findsNothing);
  });

  testWidgets('nothing found says so', (tester) async {
    await search(tester, 'zzzz');

    expect(find.text(t.settings.searchEmpty(query: 'zzzz')), findsOneWidget);
  });

  testWidgets('a result opens its screen with the setting in view', (
    tester,
  ) async {
    await search(tester, 'contribute');
    tester.view.physicalSize = const Size(400, 500);
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.settings.contribute));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final row = tester.getRect(find.text(t.settings.contribute));
    expect(row.top, greaterThanOrEqualTo(0));
    expect(row.bottom, lessThanOrEqualTo(500));
  });

  testWidgets('every entry is on the screen it opens', (tester) async {
    await pumpTestApp(tester, const SettingsScreen());
    await settle(tester);
    final entries = settingsSearchIndex(t, appVersion: '1.4.2');

    final missing = <String>[];
    for (final entry in entries) {
      final open = entry.open;
      if (open == null) {
        if (find.text(entry.title).evaluate().isEmpty) {
          missing.add('${entry.title} (Settings)');
        }
        continue;
      }
      await pumpTestApp(tester, open());
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      if (find.text(entry.title).evaluate().isEmpty) {
        missing.add('${entry.title} (${entry.place})');
      }
    }

    expect(missing, isEmpty);
  });
}

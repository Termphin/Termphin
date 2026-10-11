import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/settings/release_notes_screen.dart';
import 'package:termphin/services/app/release_notes_service.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = AppLocale.en.buildSync();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the changelog loads the bundled history', (tester) async {
    await pumpTestApp(tester, const ReleaseNotesScreen());
    await tester.pumpAndSettle();

    expect(find.text(t.settings.releaseNotes), findsOneWidget);

    for (final version in ['v1.1.0', 'v1.0.0']) {
      await tester.scrollUntilVisible(
        find.text(version),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(version), findsOneWidget);
    }
  });

  testWidgets('the newest version starts expanded, older ones collapsed', (
    tester,
  ) async {
    final entries = await ReleaseNotesService.instance.allEntries();
    final newest = entries.first.version;
    final heading = entries.first.categories.first.label.toUpperCase();

    await pumpTestApp(tester, const ReleaseNotesScreen());
    await tester.pumpAndSettle();

    expect(find.text(heading), findsOneWidget);

    await tester.tap(find.text('v$newest'));
    await tester.pumpAndSettle();

    expect(find.text(heading), findsNothing);
  });

  testWidgets('no version shows a date', (tester) async {
    final entries = await ReleaseNotesService.instance.allEntries();

    await pumpTestApp(tester, const ReleaseNotesScreen());
    await tester.pumpAndSettle();

    expect(find.text('v${entries.first.version}'), findsOneWidget);
    for (final entry in entries) {
      expect(find.text(entry.date), findsNothing);
    }
  });
}

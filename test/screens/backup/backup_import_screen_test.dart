import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/backup/backup_import_screen.dart';
import 'package:termphin/widgets/ui/backup_action_bar.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  testWidgets('opens on the file picker, not on a list of switches', (
    tester,
  ) async {
    await pumpTestApp(tester, const BackupImportScreen());
    await tester.pumpAndSettle();

    expect(find.text(t.exportScreen.selectFile), findsOneWidget);
    expect(find.text(t.exportScreen.noFileChosen), findsOneWidget);
    expect(find.text(t.exportScreen.whatToImport.toUpperCase()), findsNothing);
  });

  testWidgets('keeps its action out of the scroll', (tester) async {
    await pumpTestApp(tester, const BackupImportScreen());
    await tester.pumpAndSettle();

    final bar = find.byType(BackupActionBar);
    expect(bar, findsOneWidget);
    expect(
      find.ancestor(of: bar, matching: find.byType(Scrollable)),
      findsNothing,
    );
  });
}

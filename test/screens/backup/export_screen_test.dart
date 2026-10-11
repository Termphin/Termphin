import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/backup/backup_export_screen.dart';
import 'package:termphin/screens/backup/backup_import_screen.dart';
import 'package:termphin/screens/backup/export_screen.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  testWidgets('is a fork, not both halves at once', (tester) async {
    await pumpTestApp(tester, const ExportScreen());
    await tester.pumpAndSettle();

    expect(find.text(t.exportScreen.exportSection), findsOneWidget);
    expect(find.text(t.exportScreen.importSection), findsOneWidget);
    expect(find.text(t.exportScreen.includeSshProfiles), findsNothing);
    expect(find.text(t.exportScreen.selectFile), findsNothing);
  });

  testWidgets('each row opens its own screen', (tester) async {
    await pumpTestApp(tester, const ExportScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.exportScreen.exportSection));
    await tester.pumpAndSettle();
    expect(find.byType(BackupExportScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.exportScreen.importSection));
    await tester.pumpAndSettle();
    expect(find.byType(BackupImportScreen), findsOneWidget);
  });
}

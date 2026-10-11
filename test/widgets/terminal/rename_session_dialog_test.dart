import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/terminal/rename_session_dialog.dart';

import '../../support/test_app.dart';

/// Covers the prefix-lock behavior: sessions this app created (`termphin_*`)
/// must keep that prefix through a rename, so the app can keep telling its
/// own sessions apart from ones the user made by hand. Sessions found
/// through the server-sessions browser that never had the prefix stay freely
/// editable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(
    WidgetTester tester, {
    required String currentName,
    required Future<void> Function(String) onRename,
  }) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRenameSessionDialog(
              context,
              currentName: currentName,
              onRename: onRename,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'an owned session only lets the suffix be edited, prefix stays fixed',
    (tester) async {
      String? renamedTo;
      await pumpDialog(
        tester,
        currentName: 'termphin_a3f9c1',
        onRename: (name) async => renamedTo = name,
      );

      expect(find.text('termphin_'), findsNothing);
      expect(find.text('termphin_a3f9c1'), findsNothing);
      expect(find.text('a3f9c1'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'deploy-box');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(renamedTo, 'termphin_deploy-box');
    },
  );

  testWidgets('a foreign session name is freely editable, no prefix forced', (
    tester,
  ) async {
    String? renamedTo;
    await pumpDialog(
      tester,
      currentName: 'deploy',
      onRename: (name) async => renamedTo = name,
    );

    expect(find.text('termphin_'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'staging');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamedTo, 'staging');
  });

  testWidgets('rejects a suffix containing a dot or colon', (tester) async {
    var renamed = false;
    await pumpDialog(
      tester,
      currentName: 'termphin_a3f9c1',
      onRename: (name) async => renamed = true,
    );

    await tester.enterText(find.byType(TextFormField), 'bad.name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamed, isFalse);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('saving the same name does not call onRename', (tester) async {
    var renamed = false;
    await pumpDialog(
      tester,
      currentName: 'termphin_a3f9c1',
      onRename: (name) async => renamed = true,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamed, isFalse);
  });
}

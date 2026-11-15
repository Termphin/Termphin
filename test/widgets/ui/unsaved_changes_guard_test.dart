import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/screens/snippets/snippet_form_screen.dart';
import 'package:termphin/widgets/ui/unsaved_changes_guard.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  /// A home screen with a button that pushes [form], so there is somewhere
  /// for the form to go back to.
  Future<void> openOver(WidgetTester tester, Widget form) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => form)),
          child: const Text('home'),
        ),
      ),
    );
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();
  }

  Future<void> goBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  group('UnsavedChangesGuard', () {
    testWidgets('with nothing changed, back leaves at once', (tester) async {
      await openOver(
        tester,
        UnsavedChangesGuard(dirty: () => false, child: const Text('form')),
      );

      await goBack(tester);

      expect(find.text('form'), findsNothing);
      expect(find.text(t.common.unsavedTitle), findsNothing);
    });

    testWidgets('with changes, back asks; staying keeps the form', (
      tester,
    ) async {
      await openOver(
        tester,
        UnsavedChangesGuard(dirty: () => true, child: const Text('form')),
      );

      await goBack(tester);
      expect(find.text(t.common.unsavedTitle), findsOneWidget);

      await tester.tap(find.text(t.common.cancel));
      await tester.pumpAndSettle();
      expect(find.text('form'), findsOneWidget);

      await goBack(tester);
      await tester.tap(find.text(t.common.discard));
      await tester.pumpAndSettle();
      expect(find.text('form'), findsNothing);
    });
  });

  testWidgets('a snippet with a typed name asks before its close button '
      'throws it away', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openOver(tester, const SnippetFormScreen());

    await tester.tap(find.byTooltip(t.common.close));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'deploy');
    await tester.pump();
    await tester.tap(find.byTooltip(t.common.close));
    await tester.pumpAndSettle();

    expect(find.text(t.common.unsavedTitle), findsOneWidget);
  });
}

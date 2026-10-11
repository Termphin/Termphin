import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/providers/profiles_provider.dart';
import 'package:termphin/widgets/profiles/profile_form_dialog.dart';
import '../../support/fakes.dart';
import '../../support/test_app.dart';

void main() {
  testWidgets('probe', (tester) async {
    final storage = FakeProfileStorage();
    final container = ProviderContainer.test(
      overrides: [profileStorageProvider.overrideWithValue(storage)],
    );
    await pumpTestApp(tester, const ProfileFormDialog(), container: container);
    await tester.pumpAndSettle();
    debugPrint('FIELDS=${find.byType(TextFormField).evaluate().length}');
    debugPrint('TEXTBUTTONS=${find.byType(TextButton).evaluate().length}');
    for (final e in find.byType(TextButton).evaluate()) {
      debugPrint('  btn: ${e.widget}');
    }
    debugPrint(
      'SAVE=${find.widgetWithText(TextButton, 'Save').evaluate().length}',
    );
    debugPrint(
      'NAME=${find.widgetWithText(TextFormField, 'Name').evaluate().length}',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/app/legal_updates_service.dart';
import 'package:termphin/widgets/onboarding/legal_update_dialog.dart';

import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();

  testWidgets('says what changed, links both documents and closes on Got it', (
    tester,
  ) async {
    const update = LegalUpdate(
      id: '2026-11-15',
      material: true,
      summary: 'Pro arrived.',
    );
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showLegalUpdateDialog(context, update),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(t.legalUpdate.title), findsOneWidget);
    expect(find.text('Pro arrived.'), findsOneWidget);
    expect(find.text(t.analyticsConsent.termsLink), findsOneWidget);
    expect(find.text(t.analyticsConsent.privacyLink), findsOneWidget);

    await tester.tap(find.text(t.legalUpdate.gotIt));
    await tester.pumpAndSettle();

    expect(find.text(t.legalUpdate.title), findsNothing);
  });
}

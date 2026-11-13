import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/widgets/account/account_avatar_button.dart';

import '../../support/fake_account_backend.dart';
import '../../support/test_app.dart';

void main() {
  final t = AppLocale.en.buildSync();
  late FakeAccountBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAccountBackend();
    AccountService.backendOverride = () => backend;
    AccountService.instance.resetForTest();
  });

  tearDown(() {
    AccountService.backendOverride = null;
    AccountService.instance.resetForTest();
  });

  Future<void> show(WidgetTester tester) => pumpTestApp(
    tester,
    Scaffold(appBar: AppBar(actions: const [AccountAvatarButton()])),
  );

  testWidgets('signed out, it is an empty silhouette', (tester) async {
    await show(tester);

    expect(find.byIcon(PhosphorIconsRegular.userCircle), findsOneWidget);
  });

  testWidgets('signed in, it is the first letter of the address', (
    tester,
  ) async {
    await AccountService.instance.signInWithGoogle();

    await show(tester);
    await tester.pump();

    expect(find.text('M'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.userCircle), findsNothing);
  });

  testWidgets('a tap opens the account', (tester) async {
    await show(tester);

    await tester.tap(find.byTooltip(t.account.title));
    await tester.pumpAndSettle();

    expect(find.text(t.account.continueWithGoogle), findsOneWidget);
  });

  testWidgets('a build without accounts shows nothing', (tester) async {
    AccountService.backendOverride = null;

    await show(tester);

    expect(find.byType(IconButton), findsNothing);
  });

  test('the letter is the name first, then the address', () {
    expect(
      AccountAvatarButton.initialOf(
        const AccountUser(
          uid: 'u',
          provider: AccountProvider.google,
          displayName: 'zofia',
          email: 'me@example.com',
        ),
      ),
      'Z',
    );
    expect(
      AccountAvatarButton.initialOf(
        const AccountUser(uid: 'u', provider: AccountProvider.apple),
      ),
      '?',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/screens/settings/account_screen.dart';
import 'package:termphin/services/account/account_service.dart';
import 'package:termphin/widgets/account/account_avatar_button.dart';

import '../../support/fake_account_backend.dart';
import '../../support/test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountService.backendOverride = FakeAccountBackend.new;
    AccountService.instance.resetForTest();
  });

  tearDown(() {
    AccountService.backendOverride = null;
    AccountService.instance.resetForTest();
  });

  testWidgets('opens the account screen through the app navigator on a click', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await pumpTestApp(
      tester,
      Navigator(
        key: navigator,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              actions: [
                TitleBarAccountButton(
                  navigatorContext: () => navigator.currentContext,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final avatar = tester.getSize(
      find.byKey(const ValueKey('titleBarAccount')),
    );
    expect(avatar.height, lessThan(32));

    await tester.tap(find.byKey(const ValueKey('titleBarAccount')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
  });
}

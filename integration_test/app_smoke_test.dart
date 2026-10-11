import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:termphin/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches and navigates between the primary screens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SshClientApp());
    await tester.pumpAndSettle();

    expect(find.text('Your machines'), findsOneWidget);

    await tester.tap(find.text('Keys'));
    await tester.pumpAndSettle();
    expect(find.text('SSH Keys'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
  });
}

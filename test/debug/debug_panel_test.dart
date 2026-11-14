import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/debug/debug_panel.dart';

void main() {
  testWidgets('the button over the app opens the panel', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            DebugPanel(navigatorKey: navigatorKey, child: child!),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pumpAndSettle();

    expect(find.text('Open the paywall'), findsOneWidget);
  });
}

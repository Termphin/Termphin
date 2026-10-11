import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ui/app_notifications.dart';

import '../../support/test_app.dart';

/// `AppNotifications` keeps its overlay entry in a static, so it outlives the
/// tree that raised the first toast. Whatever replaces that tree has to end up
/// with a working host rather than a reference to a dead one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget screen(String label) => Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => AppNotifications.info(context, label),
          child: Text('raise $label'),
        ),
      ),
    ),
  );

  testWidgets('a toast still shows after the overlay under it was replaced', (
    tester,
  ) async {
    await pumpTestApp(tester, screen('first'));
    await tester.tap(find.text('raise first'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    await pumpTestApp(tester, screen('second'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('raise second'));
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raising two toasts in a row reuses the same host', (
    tester,
  ) async {
    await pumpTestApp(tester, screen('one'));
    await tester.tap(find.text('raise one'));
    await tester.pump();
    await tester.tap(find.text('raise one'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('one'), findsWidgets);
  });

  testWidgets('two toasts raised in one frame, before the host is built', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                AppNotifications.error(context, 'failed');
                AppNotifications.info(context, 'details');
              },
              child: const Text('raise both'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('raise both'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('details'), findsOneWidget);
  });
}

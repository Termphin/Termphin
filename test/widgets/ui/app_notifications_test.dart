import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ui/app_notifications.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps a screen with a button per message, so a test can raise them in
  /// whatever order it needs from a context that is inside the app.
  Future<void> pumpHost(WidgetTester tester, List<String> messages) async {
    await pumpTestApp(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('screen')),
        body: Builder(
          builder: (context) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final message in messages)
                ElevatedButton(
                  onPressed: () => AppNotifications.info(context, message),
                  child: Text('show $message'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('the first notification survives the frame the host mounts on', (
    tester,
  ) async {
    await pumpHost(tester, ['one']);
    await tester.tap(find.text('show one'));
    await tester.pumpAndSettle();

    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('a notification lands below the app bar', (tester) async {
    await pumpHost(tester, ['one']);
    await tester.tap(find.text('show one'));
    await tester.pumpAndSettle();

    final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(tester.getRect(find.text('one')).top, greaterThan(appBarBottom));
  });

  testWidgets('it goes away on its own', (tester) async {
    await pumpHost(tester, ['one']);
    await tester.tap(find.text('show one'));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
  });

  testWidgets('a burst stacks instead of queueing, oldest dropped', (
    tester,
  ) async {
    await pumpHost(tester, ['one', 'two', 'three', 'four']);
    for (final message in ['one', 'two', 'three', 'four']) {
      await tester.tap(find.text('show $message'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('one'), findsNothing);
    for (final message in ['two', 'three', 'four']) {
      expect(find.text(message), findsOneWidget);
    }
    expect(
      tester.getRect(find.text('four')).top,
      lessThan(tester.getRect(find.text('two')).top),
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping one clears the whole stack', (tester) async {
    await pumpHost(tester, ['one', 'two', 'three']);
    for (final message in ['one', 'two', 'three']) {
      await tester.tap(find.text('show $message'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();

    for (final message in ['one', 'two', 'three']) {
      expect(find.text(message), findsNothing);
    }
  });

  testWidgets('the stack expires together, on the newest card\'s deadline', (
    tester,
  ) async {
    await pumpHost(tester, ['one', 'two']);
    await tester.tap(find.text('show one'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('show two'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsNothing);
  });

  testWidgets('an action toast is not cut short by a plain one landing on it', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton(
                onPressed: () => AppNotifications.success(
                  context,
                  'undoable',
                  actionLabel: 'Undo',
                  onAction: () {},
                ),
                child: const Text('show action'),
              ),
              ElevatedButton(
                onPressed: () => AppNotifications.info(context, 'plain'),
                child: const Text('show plain'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('show action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('show plain'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('undoable'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('undoable'), findsNothing);
  });

  testWidgets('a card grows to fit the lines its message wraps onto', (
    tester,
  ) async {
    const short = 'Copied.';
    const long =
        'The remote host closed the connection while a file was still '
        'uploading, so the transfer was left incomplete and nothing was '
        'written to the destination path.';

    Future<double> cardHeight(String message) async {
      await pumpHost(tester, [message]);
      await tester.tap(find.text('show $message'));
      await tester.pumpAndSettle();
      final height = tester
          .getRect(
            find
                .ancestor(
                  of: find.text(message),
                  matching: find.byType(Material),
                )
                .first,
          )
          .height;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      return height;
    }

    expect(await cardHeight(long), greaterThan(await cardHeight(short)));
  });

  testWidgets('an action runs and closes the notification', (tester) async {
    var tapped = 0;
    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AppNotifications.success(
              context,
              'done',
              actionLabel: 'Undo',
              onAction: () => tapped++,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(find.text('done'), findsNothing);
  });

  testWidgets('a swipe up on one card dismisses the stack early', (
    tester,
  ) async {
    await pumpHost(tester, ['one', 'two']);
    for (final message in ['one', 'two']) {
      await tester.tap(find.text('show $message'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await tester.fling(find.text('two'), const Offset(0, -60), 800);
    await tester.pumpAndSettle();

    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsNothing);
  });
}

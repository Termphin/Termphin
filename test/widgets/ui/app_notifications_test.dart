import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/theme/theme.dart';
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

  testWidgets('a notification drops in at the top, over the app bar', (
    tester,
  ) async {
    await pumpHost(tester, ['one']);
    await tester.tap(find.text('show one'));
    await tester.pumpAndSettle();

    final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(tester.getRect(find.text('one')).bottom, lessThan(appBarBottom));
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

  testWidgets('a long message wraps onto more lines instead of being cut', (
    tester,
  ) async {
    const short = 'Copied.';
    const long =
        'The remote host closed the connection while a file was still '
        'uploading, so the transfer was left incomplete and nothing was '
        'written to the destination path.';

    Future<double> textHeight(String message) async {
      await pumpHost(tester, [message]);
      await tester.tap(find.text('show $message'));
      await tester.pumpAndSettle();
      final height = tester.getRect(find.text(message)).height;
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      return height;
    }

    expect(await textHeight(long), greaterThan(await textHeight(short) * 2));
  });

  testWidgets('a short message is a pill, a long one a card', (tester) async {
    Finder byName(String name) => find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == name,
    );

    await pumpHost(tester, [
      'Copied.',
      'The remote host closed the connection while a file was still '
          'uploading, so nothing was written.',
    ]);
    await tester.tap(find.text('show Copied.'));
    await tester.pumpAndSettle();
    expect(byName('_Pill'), findsOneWidget);
    expect(byName('_Card'), findsNothing);

    await tester.tap(find.textContaining('show The remote host'));
    await tester.pumpAndSettle();
    expect(byName('_Card'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
  });

  testWidgets('the same message again is counted, not stacked', (tester) async {
    await pumpHost(tester, ['one']);
    await tester.tap(find.text('show one'));
    await tester.pump();
    await tester.tap(find.text('show one'));
    await tester.pumpAndSettle();

    expect(find.text('one'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  group('how long one stays', () {
    Duration of(
      AppNotificationKind kind,
      String message, {
      bool action = false,
    }) => AppNotifications.durationFor(kind, message, hasAction: action);

    test('a short confirmation is up for the shortest time', () {
      expect(
        of(AppNotificationKind.success, 'Copied'),
        const Duration(seconds: 4),
      );
    });

    test('an error stays longer than a confirmation of the same length', () {
      expect(
        of(AppNotificationKind.error, 'Copied'),
        greaterThan(of(AppNotificationKind.success, 'Copied')),
      );
    });

    test('a longer message stays longer, up to the cap', () {
      final medium = of(AppNotificationKind.info, 'x' * 80);
      expect(medium, greaterThan(of(AppNotificationKind.info, 'x' * 20)));
      expect(
        of(AppNotificationKind.info, 'x' * 1000),
        const Duration(seconds: 8),
      );
    });

    test('an alert from a session outlasts everything else', () {
      expect(
        of(AppNotificationKind.alert, 'done', action: true),
        greaterThan(of(AppNotificationKind.success, 'Done', action: true)),
      );
      expect(
        of(AppNotificationKind.alert, 'done', action: true),
        greaterThan(of(AppNotificationKind.error, 'x' * 1000)),
      );
    });

    test('an action gets more time, however short', () {
      expect(
        of(AppNotificationKind.success, 'Done', action: true),
        const Duration(seconds: 8),
      );
    });
  });

  group('haptics', () {
    late List<String> buzzes;

    setUp(() {
      buzzes = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              buzzes.add(call.arguments as String);
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Future<void> raise(
      WidgetTester tester,
      void Function(BuildContext context) show,
    ) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => show(context),
              child: const Text('show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
    }

    testWidgets('a confirmation is silent', (tester) async {
      await raise(tester, (context) => AppNotifications.success(context, 'ok'));
      expect(buzzes, isEmpty);
    });

    testWidgets('an error buzzes once', (tester) async {
      await raise(tester, (context) => AppNotifications.error(context, 'no'));
      expect(buzzes, hasLength(1));
    });

    testWidgets('an alert buzzes twice', (tester) async {
      await raise(
        tester,
        (context) => AppNotifications.alert(
          context,
          title: 'build finished',
          body: 'done',
          actionLabel: 'Open',
          onOpen: () {},
        ),
      );
      expect(buzzes, hasLength(2));
    });
  });

  testWidgets('a tap anywhere on an alert opens it and clears the stack', (
    tester,
  ) async {
    var opened = 0;
    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AppNotifications.alert(
              context,
              title: 'dnf update finished',
              body: 'Complete!',
              actionLabel: 'Open',
              onOpen: () => opened++,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete!'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.text('dnf update finished'), findsNothing);
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

  testWidgets('light theme drops the shadow from notification pills and cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => AppNotifications.info(context, 'pill'),
                    child: const Text('pill'),
                  ),
                  ElevatedButton(
                    onPressed: () => AppNotifications.success(
                      context,
                      'card',
                      actionLabel: 'Undo',
                      onAction: () {},
                    ),
                    child: const Text('card'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('pill'));
    await tester.pumpAndSettle();
    final pillContainer = tester.widget<Container>(
      find.ancestor(
        of: find.text('pill').last,
        matching: find.byType(Container),
      ).first,
    );
    expect((pillContainer.decoration as BoxDecoration).boxShadow, isNull);

    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();
    final cardMaterial = tester.widget<Material>(
      find.ancestor(
        of: find.text('Undo'),
        matching: find.byType(Material),
      ).first,
    );
    expect(cardMaterial.elevation, 0);
  });
}

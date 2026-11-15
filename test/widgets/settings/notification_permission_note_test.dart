import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/widgets/settings/notification_permission_note.dart';

import '../../support/test_app.dart';

void main() {
  final warning = find.text(t.settings.notificationsBlocked);

  Future<void> show(
    WidgetTester tester, {
    required Future<bool> Function() hasPermission,
    Future<bool> Function()? requestPermission,
  }) async {
    await pumpTestApp(
      tester,
      NotificationPermissionNote(
        hasPermission: hasPermission,
        requestPermission: requestPermission ?? () async => false,
      ),
    );
    await tester.pump();
  }

  testWidgets('blocked notifications get a warning', (tester) async {
    await show(tester, hasPermission: () async => false);

    expect(warning, findsOneWidget);
    expect(find.text(t.settings.notificationsBlockedAction), findsOneWidget);
  });

  testWidgets('allowed notifications get nothing', (tester) async {
    await show(tester, hasPermission: () async => true);

    expect(warning, findsNothing);
  });

  testWidgets('a tap asks for the permission and the warning goes once it '
      'is given', (tester) async {
    var granted = false;
    var asked = 0;
    await show(
      tester,
      hasPermission: () async => granted,
      requestPermission: () async {
        asked++;
        return granted = true;
      },
    );

    await tester.tap(warning);
    await tester.pump();

    expect(asked, 1);
    expect(warning, findsNothing);
  });

  testWidgets('allowing it on the system screen clears the warning on the '
      'way back', (tester) async {
    var granted = false;
    await show(tester, hasPermission: () async => granted);
    expect(warning, findsOneWidget);

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(warning, findsNothing);
  });

  group('the permission row', () {
    Future<void> row(
      WidgetTester tester, {
      required Future<bool> Function() hasPermission,
      Future<bool> Function()? requestPermission,
      Future<void> Function()? openSettings,
    }) async {
      await pumpTestApp(
        tester,
        NotificationPermissionRow(
          hasPermission: hasPermission,
          requestPermission: requestPermission ?? () async => false,
          openSettings: openSettings ?? () async {},
        ),
      );
      await tester.pump();
    }

    testWidgets('allowed, a tap opens the system page', (tester) async {
      var opened = 0;
      var asked = 0;
      await row(
        tester,
        hasPermission: () async => true,
        requestPermission: () async {
          asked++;
          return true;
        },
        openSettings: () async => opened++,
      );

      expect(find.text(t.common.allowed), findsOneWidget);
      await tester.tap(find.text(t.settings.notificationsPermission));
      await tester.pump();

      expect(opened, 1);
      expect(asked, 0);
    });

    testWidgets('not allowed, a tap asks and the row follows', (tester) async {
      var granted = false;
      await row(
        tester,
        hasPermission: () async => granted,
        requestPermission: () async => granted = true,
      );
      expect(find.text(t.common.allow), findsOneWidget);

      await tester.tap(find.text(t.settings.notificationsPermission));
      await tester.pump();

      expect(find.text(t.common.allowed), findsOneWidget);
    });
  });
}

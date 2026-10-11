import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/utils/platform_info.dart';
import 'package:termphin/widgets/ui/app_form_field.dart';
import 'package:termphin/widgets/ui/cursor_menu.dart';
import 'package:termphin/widgets/ui/permission_tile.dart';

import '../../support/test_app.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await pumpTestApp(tester, Scaffold(body: child));
  await tester.pumpAndSettle();
}

void main() {
  final t = AppLocale.en.buildSync();

  group('AppFormField', () {
    testWidgets('shows its label and hint and takes text', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        AppFormField(
          controller: controller,
          label: 'Host',
          hint: 'example.com',
        ),
      );

      expect(find.text('Host'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'db.internal');
      expect(controller.text, 'db.internal');
    });

    testWidgets('hides what it is told to hide', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        AppFormField(controller: controller, label: 'Password', obscure: true),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
    });

    testWidgets('shows a plain field by default', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, AppFormField(controller: controller));
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
    });
  });

  group('PermissionTile', () {
    testWidgets('offers to allow what is not granted', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        PermissionTile(
          title: 'Notifications',
          subtitle: 'Needed while a session is live',
          granted: false,
          onTap: () => taps++,
        ),
      );

      expect(find.text(t.common.allow), findsOneWidget);
      expect(find.text(t.common.allowed), findsNothing);

      await tester.tap(find.text('Notifications'));
      expect(taps, 1);
    });

    testWidgets('reports what is already granted', (tester) async {
      await _pump(
        tester,
        const PermissionTile(
          title: 'Notifications',
          subtitle: 'Granted',
          granted: true,
          onTap: null,
        ),
      );

      expect(find.text(t.common.allowed), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('CursorMenu', () {
    Future<Offset> menuAt(WidgetTester tester, Offset anchor) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [
              CursorMenu(
                anchor: anchor,
                onDismiss: () {},
                child: const SizedBox(width: 240, height: 52, key: Key('menu')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.byKey(const Key('menu')));
    }

    testWidgets('sits where it was anchored', (tester) async {
      expect(
        await menuAt(tester, const Offset(100, 200)),
        const Offset(100, 200),
      );
    });

    testWidgets('is kept off the left and top edges', (tester) async {
      expect(await menuAt(tester, Offset.zero), const Offset(8, 8));
    });

    testWidgets('is pulled back from the right and bottom', (tester) async {
      final at = await menuAt(tester, const Offset(5000, 5000));
      expect(at.dx, lessThan(800));
      expect(at.dy, lessThan(1000));
    });

    testWidgets('a tap anywhere else dismisses it', (tester) async {
      var dismissed = 0;
      await pumpTestApp(
        tester,
        Scaffold(
          body: Stack(
            children: [
              CursorMenu(
                anchor: const Offset(400, 500),
                onDismiss: () => dismissed++,
                child: const SizedBox(width: 240, height: 52),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    });
  });

  group('isWideLayout', () {
    testWidgets('is true in landscape', (tester) async {
      late bool wide;
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              wide = isWideLayout(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(wide, isTrue);
    });

    testWidgets('is false on a portrait phone', (tester) async {
      late bool wide;
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              wide = isWideLayout(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(wide, isFalse);
    });
  });
}

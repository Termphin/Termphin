import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/utils/platform_info.dart';
import 'package:termphin/widgets/ui/app_sheet.dart';
import 'package:termphin/widgets/ui/section_navigator.dart';
import 'package:termphin/widgets/ui/sheet_handle.dart';

import '../../support/test_app.dart';

/// A host with one button that runs [onPressed] with its own context.
class _Launcher extends StatelessWidget {
  const _Launcher(this.onPressed);

  final void Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => onPressed(context),
        child: const Text('open'),
      ),
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Text('body of $title'),
  );
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    desktopBreadcrumb.value = const [];
  });

  group('platformHas', () {
    test('a desktop has no touch controls and draws its own window', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(isDesktopPlatform, isTrue);
      expect(platformHas(PlatformFeature.touchControls), isFalse);
      expect(platformHas(PlatformFeature.customWindowChrome), isTrue);
      expect(platformHas(PlatformFeature.notificationPermission), isFalse);
      expect(platformHas(PlatformFeature.biometrics), isFalse);
      expect(platformHas(PlatformFeature.embeddedWebView), isFalse);
      expect(platformHas(PlatformFeature.downloadFolderPicker), isTrue);
    });

    test('a Mac keeps the system menu bar and biometrics', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(platformHas(PlatformFeature.nativeMenuBar), isTrue);
      expect(platformHas(PlatformFeature.biometrics), isTrue);
      expect(platformHas(PlatformFeature.embeddedWebView), isTrue);
    });

    test('a phone keeps everything it had', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isDesktopPlatform, isFalse);
      expect(platformHas(PlatformFeature.touchControls), isTrue);
      expect(platformHas(PlatformFeature.foregroundService), isTrue);
      expect(platformHas(PlatformFeature.customWindowChrome), isFalse);
    });
  });

  group('showAppSheet', () {
    testWidgets('is a bottom sheet with a handle on a phone', (tester) async {
      await pumpTestApp(
        tester,
        _Launcher(
          (context) => showAppSheet<void>(
            context: context,
            builder: (_) => const Text('content'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('is a dialog without a grab handle on a desktop, closed by '
        'Esc', (tester) async {
      await pumpTestApp(
        tester,
        _Launcher(
          (context) => showAppSheet<void>(
            context: context,
            builder: (_) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [SheetHandle(), Text('content')],
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SheetHandle),
          matching: find.byType(Container),
        ),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('content'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('pushAppForm', () {
    testWidgets('is a full-screen page on a phone', (tester) async {
      await pumpTestApp(
        tester,
        _Launcher(
          (context) =>
              pushAppForm<void>(context, builder: (_) => const _Page('Form')),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('body of Form'), findsOneWidget);
    });

    testWidgets('is a dialog on a desktop that a stray click leaves open and '
        'Esc closes', (tester) async {
      await pumpTestApp(
        tester,
        _Launcher(
          (context) =>
              pushAppForm<void>(context, builder: (_) => const _Page('Form')),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('body of Form'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('body of Form'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  testWidgets('Esc closes a desktop form even with a field in it focused - a '
      'Scaffold answers Esc itself, for its drawer', (tester) async {
    await pumpTestApp(
      tester,
      _Launcher(
        (context) => pushAppForm<void>(
          context,
          builder: (_) => const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  group('pushAppPage in a section', () {
    Future<void> pumpSection(WidgetTester tester) async {
      await pumpTestApp(
        tester,
        Row(
          children: [
            const SizedBox(width: 100, child: Text('sidebar')),
            Expanded(
              child: SectionNavigator(
                label: 'Settings',
                active: true,
                child: _Launcher(
                  (context) => pushAppPage<void>(
                    context,
                    title: 'Appearance',
                    builder: (_) => const _Page('Appearance'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    testWidgets('opens beside the sidebar with no back arrow, and the path '
        'is published for the title bar', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('body of Appearance'), findsOneWidget);
      expect(find.text('sidebar'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(desktopBreadcrumb.value.map((e) => e.label), [
        'Settings',
        'Appearance',
      ]);

      desktopBreadcrumb.value.first.onTap!();
      await tester.pumpAndSettle();
      expect(find.text('body of Appearance'), findsNothing);
      expect(desktopBreadcrumb.value, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a settings page opens as a window over the screen it came '
        'from, closed with Esc', (tester) async {
      await pumpTestApp(
        tester,
        SectionNavigator(
          label: 'Settings',
          active: true,
          child: _Launcher(
            (context) => pushAppPage<void>(
              context,
              title: 'Appearance',
              window: true,
              builder: (_) => const _Page('Appearance'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('open', skipOffstage: false), findsOneWidget);
      expect(desktopBreadcrumb.value, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('goes back up with Esc', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('body of Appearance'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('body of Appearance'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}

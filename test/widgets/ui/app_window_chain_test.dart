import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/widgets/ui/app_sheet.dart';

import '../../support/test_app.dart';

const _desktop = TargetPlatformVariant({TargetPlatform.linux});

Widget _page(String title, {Widget? body}) => Scaffold(
  appBar: AppBar(title: AppWindowTitle(child: Text(title))),
  body: body ?? const SizedBox.shrink(),
);

/// A window titled "Settings" whose page opens "Terminal" from inside it.
Future<void> _openTwo(WidgetTester tester) async {
  await pumpTestApp(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => pushAppWindow<void>(
          context,
          title: 'Settings',
          builder: (context) => _page(
            'Settings',
            body: TextButton(
              onPressed: () => pushAppWindow<void>(
                context,
                title: 'Terminal',
                builder: (_) => _page('Terminal'),
              ),
              child: const Text('open terminal'),
            ),
          ),
        ),
        child: const Text('open settings'),
      ),
    ),
  );
  await tester.tap(find.text('open settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open terminal'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a window opened from a window goes back, not closed', (
    tester,
  ) async {
    await _openTwo(tester);

    expect(find.byIcon(PhosphorIconsRegular.x), findsOneWidget);
    expect(find.byType(BackButton), findsNWidgets(2));

    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();

    expect(find.text('Terminal'), findsNothing);
    expect(find.text('open terminal'), findsOneWidget);
  }, variant: _desktop);

  testWidgets('the path in its title leads back to the window it came from', (
    tester,
  ) async {
    await _openTwo(tester);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('open terminal'), findsOneWidget);
    expect(find.text('Terminal'), findsNothing);
  }, variant: _desktop);

  testWidgets('Esc closes every window of the chain at once', (tester) async {
    await _openTwo(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('open settings'), findsOneWidget);
    expect(find.text('open terminal'), findsNothing);
  }, variant: _desktop);
}

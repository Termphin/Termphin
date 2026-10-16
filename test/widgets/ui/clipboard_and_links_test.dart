import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ui/clipboard_and_links.dart';

import '../../support/platform_mocks.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  testWidgets('puts the text on the clipboard and confirms it', (tester) async {
    final clipboard = ClipboardMock()..install();
    addTearDown(clipboard.uninstall);

    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => copyToClipboard(context, 'hello'),
            child: const Text('copy'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('copy'));
    await tester.pumpAndSettle();

    expect(clipboard.text, 'hello');
    expect(find.text('Copied.'), findsOneWidget);
  });

  testWidgets('shows a custom message when given one', (tester) async {
    final clipboard = ClipboardMock()..install();
    addTearDown(clipboard.uninstall);

    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                copyToClipboard(context, 'hello', message: 'Custom message'),
            child: const Text('copy'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('copy'));
    await tester.pumpAndSettle();

    expect(find.text('Custom message'), findsOneWidget);
  });

  testWidgets('shows the failure message when nothing can open the url', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          switch (call.method) {
            case 'launch':
              return false;
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, null),
    );

    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => openExternalUrl(
              context,
              Uri.parse('https://termphin.dev'),
              failureMessage: 'Could not open it',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open it'), findsOneWidget);
  });

  testWidgets('shows the generic failure message when none is given', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlLauncherChannel, (call) async {
          switch (call.method) {
            case 'launch':
              return false;
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, null),
    );

    await pumpTestApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                openExternalUrl(context, Uri.parse('https://termphin.dev')),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open your browser.'), findsOneWidget);
  });
}

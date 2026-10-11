import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/utils/link_metadata.dart';
import 'package:termphin/widgets/terminal/link_preview_popup.dart';

import '../../support/platform_mocks.dart';
import '../../support/test_app.dart';

void main() {
  group('linkPopupTop', () {
    double top(double tapY, {double keyboard = 0}) => linkPopupTop(
      tapY: tapY,
      screenHeight: 800,
      keyboardInset: keyboard,
      popupHeight: 160,
    );

    test('opens below a tap in the top half, above one in the bottom', () {
      expect(top(100), 112);
      expect(top(600), 428);
    });

    test('never reaches under the keyboard', () {
      expect(top(300, keyboard: 300), 128);
      expect(top(380, keyboard: 300) + 160, lessThanOrEqualTo(500 - 12));
    });

    test('pins to the top when the keyboard leaves no room', () {
      expect(top(50, keyboard: 700), 12);
    });
  });

  final t = AppLocale.en.buildSync();

  late int dismissals;
  final clipboard = ClipboardMock();

  setUp(() {
    dismissals = 0;
    clipboard.install();
    addTearDown(clipboard.uninstall);
  });

  Future<void> pump(
    WidgetTester tester,
    Future<LinkMetadata> Function(String url) fetcher, {
    String url = 'https://example.com/page',
  }) async {
    await pumpTestApp(
      tester,
      Scaffold(
        body: Stack(
          children: [
            LinkPreviewPopup(
              url: url,
              tapY: 100,
              onDismiss: () => dismissals++,
              fetcher: fetcher,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('says it is loading before anything comes back', (tester) async {
    final gate = Completer<LinkMetadata>();
    await pump(tester, (_) => gate.future);
    await tester.pump();

    expect(find.text(t.linkPreview.loading), findsOneWidget);
    gate.complete(const LinkMetadata());
    await tester.pumpAndSettle();
  });

  testWidgets('shows the page title and description it found', (tester) async {
    await pump(
      tester,
      (_) async => const LinkMetadata(
        title: 'The Title',
        description: 'What it is about',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The Title'), findsOneWidget);
    expect(find.text('What it is about'), findsOneWidget);
    expect(find.text(t.linkPreview.loading), findsNothing);
  });

  testWidgets('says so when the page had nothing to preview', (tester) async {
    await pump(tester, (_) async => const LinkMetadata());
    await tester.pumpAndSettle();

    expect(find.text(t.linkPreview.noPreview), findsOneWidget);
  });

  testWidgets(
    'a page that could not be fetched reads the same as an empty one',
    (tester) async {
      await pump(tester, (_) async => const LinkMetadata());
      await tester.pumpAndSettle();

      expect(find.text(t.linkPreview.noPreview), findsOneWidget);
      expect(find.text(t.linkPreview.copyLink), findsOneWidget);
    },
  );

  testWidgets('always offers the link itself, previewed or not', (
    tester,
  ) async {
    await pump(tester, (_) async => const LinkMetadata());
    await tester.pumpAndSettle();

    expect(find.text(t.linkPreview.copyLink), findsOneWidget);
    expect(find.textContaining('example.com'), findsWidgets);
  });

  testWidgets('copying the link dismisses the popup', (tester) async {
    await pump(tester, (_) async => const LinkMetadata());
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.linkPreview.copyLink));
    await tester.pumpAndSettle();
    expect(dismissals, 1);
    expect(clipboard.text, 'https://example.com/page');
  });

  testWidgets('fetches the url it was given', (tester) async {
    final asked = <String>[];
    await pump(tester, (url) async {
      asked.add(url);
      return const LinkMetadata();
    }, url: 'https://other.example/thing?q=1');
    await tester.pumpAndSettle();

    expect(asked, ['https://other.example/thing?q=1']);
  });
}

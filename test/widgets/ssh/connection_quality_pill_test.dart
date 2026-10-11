import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/connection_quality.dart';
import 'package:termphin/widgets/ssh/connection_quality_pill.dart';

import '../../support/test_app.dart';

void main() {
  var now = 0;
  late ConnectionQuality quality;
  var taps = 0;

  setUp(() {
    now = 0;
    taps = 0;
    quality = ConnectionQuality(clock: () => now);
  });

  Future<void> pump(WidgetTester tester) => pumpTestApp(
    tester,
    Scaffold(
      body: ConnectionQualityPill(quality: quality, onTap: () => taps++),
    ),
  );

  testWidgets('shows nothing on a good link', (tester) async {
    quality.pingSent();
    now += 40;
    quality.pingAnswered(const Duration(milliseconds: 40));
    await pump(tester);

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('names the latency on a slow link', (tester) async {
    await pump(tester);
    quality.pingSent();
    now += 420;
    quality.pingAnswered(const Duration(milliseconds: 420));
    await tester.pumpAndSettle();

    expect(find.textContaining('420 ms'), findsOneWidget);
  });

  testWidgets('counts the silence and opens the details on tap', (
    tester,
  ) async {
    await pump(tester);
    quality.pingSent();
    now += 8000;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('8s'), findsOneWidget);

    await tester.tap(find.textContaining('8s'));
    expect(taps, 1);
  });

  testWidgets('goes away once the server answers', (tester) async {
    await pump(tester);
    quality.pingSent();
    now += 8000;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    quality.pingAnswered(const Duration(milliseconds: 8000));
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing);
  });

  group('ReconnectingIndicator', () {
    Future<void> pumpIndicator(
      WidgetTester tester, {
      bool waitingForNetwork = false,
      int queuedInput = 0,
    }) => pumpTestApp(
      tester,
      Scaffold(
        body: ReconnectingIndicator(
          attempt: 2,
          secondsRemaining: 0,
          waitingForNetwork: waitingForNetwork,
          queuedInput: queuedInput,
          onTap: () => taps++,
        ),
      ),
    );

    testWidgets('says nothing in words over the terminal', (tester) async {
      await pumpIndicator(tester);

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('spins while it is trying', (tester) async {
      await pumpIndicator(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does not spin while there is no network to try', (
      tester,
    ) async {
      await pumpIndicator(tester, waitingForNetwork: true);

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('keeps the words for a long press and a screen reader', (
      tester,
    ) async {
      await pumpIndicator(tester, queuedInput: 3);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('attempt 2'));
      expect(tooltip.message, contains('3 keys'));
    });

    testWidgets('opens the details on a tap', (tester) async {
      await pumpIndicator(tester);
      await tester.tap(find.byType(ReconnectingIndicator));
      await tester.pump();

      expect(taps, 1);
    });
  });
}

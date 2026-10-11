import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ssh/connecting_view.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the profile identity and full server log', (tester) async {
    const first = 'SSH connection established';
    const second = 'To authenticate, visit: https://example.com/auth';

    await pumpTestApp(
      tester,
      ConnectingView(
        profile: profileFixture(),
        onCancel: () {},
        connectionLog: const [first, second],
      ),
    );
    await tester.pump();

    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Connection log'), findsNothing);
    expect(find.text(first), findsOneWidget);
    expect(find.text(second), findsOneWidget);
  });

  testWidgets('scrolls to the newest server message', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messages = ValueNotifier<List<String>>(['first']);
    addTearDown(messages.dispose);

    await pumpTestApp(
      tester,
      ValueListenableBuilder<List<String>>(
        valueListenable: messages,
        builder: (_, lines, _) => ConnectingView(
          profile: profileFixture(),
          onCancel: () {},
          connectionLog: lines,
        ),
      ),
    );
    await tester.pump();

    messages.value = List.generate(40, (index) => 'message $index');
    await tester.pump();
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final position = scrollView.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('keeps the connection identity stable when logs appear', (
    tester,
  ) async {
    final messages = ValueNotifier<List<String>>([]);
    addTearDown(messages.dispose);

    await pumpTestApp(
      tester,
      ValueListenableBuilder<List<String>>(
        valueListenable: messages,
        builder: (_, lines, _) => ConnectingView(
          profile: profileFixture(),
          onCancel: () {},
          connectionLog: lines,
        ),
      ),
    );
    await tester.pump();
    final initialCenter = tester.getCenter(find.text('Production'));

    messages.value = const ['Connecting to example.com:22'];
    await tester.pump();

    expect(tester.getCenter(find.text('Production')), initialCenter);
  });

  testWidgets('hides the log area when no messages arrived', (tester) async {
    await pumpTestApp(
      tester,
      ConnectingView(profile: profileFixture(), onCancel: () {}),
    );
    await tester.pump();

    expect(find.text('Production'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}

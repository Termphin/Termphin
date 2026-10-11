import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/utils/route_pop.dart';

void main() {
  testWidgets(
    'pops target route with result when another route is stacked above it',
    (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      late Route<dynamic> route1;
      final future1 = navKey.currentState!.push<String>(
        MaterialPageRoute<String>(
          builder: (context) {
            route1 = ModalRoute.of(context)!;
            return const Scaffold(body: Text('Route 1'));
          },
        ),
      );
      await tester.pumpAndSettle();

      unawaited(
        navKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (context) => const Scaffold(body: Text('Route 2')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Route 2'), findsOneWidget);

      String? result;
      var completed = false;
      unawaited(
        future1.then((value) {
          completed = true;
          result = value;
        }),
      );

      popRouteWithResult(navKey.currentState!, route1, 'test-result');
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(result, 'test-result');
      expect(find.text('Route 2'), findsNothing);
    },
  );

  testWidgets('pops target route with result when it is the topmost route', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );

    late Route<dynamic> route1;
    final future1 = navKey.currentState!.push<String>(
      MaterialPageRoute<String>(
        builder: (context) {
          route1 = ModalRoute.of(context)!;
          return const Scaffold(body: Text('Route 1'));
        },
      ),
    );
    await tester.pumpAndSettle();

    String? result;
    var completed = false;
    unawaited(
      future1.then((value) {
        completed = true;
        result = value;
      }),
    );

    popRouteWithResult(navKey.currentState!, route1, 'test-result');
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, 'test-result');
    expect(find.text('Route 1'), findsNothing);
  });
}

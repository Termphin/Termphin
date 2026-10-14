import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:termphin/services/sftp/download_service.dart';
import 'package:termphin/services/sftp/transfer_queue.dart';
import 'package:termphin/widgets/sftp/transfer_bar.dart';

import '../../support/test_app.dart';

void main() {
  late TransferQueue queue;
  late ValueNotifier<bool> expanded;

  setUp(() {
    queue = TransferQueue();
    expanded = ValueNotifier(false);
  });

  Future<void> pump(WidgetTester tester) => pumpTestApp(
    tester,
    Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TransferBar(queue: queue, expanded: expanded),
          ),
        ],
      ),
    ),
  );

  /// Takes the bar down before the queue, then lets the queue cancel what is
  /// left and drop its linger timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
    expanded.dispose();
  }

  /// One frame to start whatever was set off, then long enough for it to
  /// finish. Not `pumpAndSettle`: a ring with no known progress spins for as
  /// long as it is shown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<T> add<T>(Completer<T> gate, {String label = 'backup.tar'}) =>
      queue.add(
        kind: TransferJobKind.upload,
        label: label,
        run: (job) => job.cancel.race(gate.future),
      );

  testWidgets('shows nothing while there is nothing to transfer', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(InkWell), findsNothing);
    await finish(tester);
  });

  testWidgets('names the running job and how far it got', (tester) async {
    await pump(tester);
    final gate = Completer<void>();
    add(gate).ignore();
    await settle(tester);
    queue.running!.report(
      const TransferProgress(
        label: 'backup.tar',
        bytes: 512,
        totalBytes: 2048,
        fraction: 0.25,
      ),
    );
    await settle(tester);

    expect(find.textContaining('512 B'), findsOneWidget);
    final fill = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fill.widthFactor, closeTo(0.25, 1e-9));
    await finish(tester);
  });

  testWidgets('counts the jobs of the run on the strip', (tester) async {
    await pump(tester);
    add(Completer<void>()).ignore();
    add(Completer<void>(), label: 'photo.jpg').ignore();
    await settle(tester);

    expect(find.textContaining('1 of 2'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a tap opens the list, and a tap outside it folds it away', (
    tester,
  ) async {
    await pump(tester);
    add(Completer<void>()).ignore();
    add(Completer<void>(), label: 'photo.jpg').ignore();
    await settle(tester);

    await tester.tap(find.byType(InkWell));
    await settle(tester);
    expect(expanded.value, isTrue);
    expect(find.text('backup.tar'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);

    await tester.tapAt(const Offset(10, 700));
    await settle(tester);
    expect(expanded.value, isFalse);
    expect(find.text('photo.jpg'), findsNothing);
    await finish(tester);
  });

  testWidgets('a waiting job can be taken off the list', (tester) async {
    await pump(tester);
    add(Completer<void>()).ignore();
    final waiting = add(Completer<void>(), label: 'photo.jpg');
    waiting.ignore();
    await settle(tester);
    expanded.value = true;
    await settle(tester);

    final row = find.ancestor(
      of: find.text('photo.jpg'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: row.first,
        matching: find.byIcon(PhosphorIconsRegular.x),
      ),
    );
    await settle(tester);

    expect(queue.jobs, hasLength(1));
    expect(find.text('photo.jpg'), findsNothing);
    await finish(tester);
  });

  testWidgets('a failed run stays, says so, and clears on request', (
    tester,
  ) async {
    await pump(tester);
    final gate = Completer<void>();
    add(gate).ignore();
    await settle(tester);
    gate.completeError(Exception('sftp.errors.diskFull'));
    await settle(tester);
    await settle(tester);

    expect(find.textContaining('1 failed'), findsOneWidget);
    await tester.tap(find.byType(InkWell).first);
    await settle(tester);
    expect(find.textContaining('space', findRichText: true), findsWidgets);

    await tester.tap(find.text('Clear'));
    await settle(tester);
    expect(queue.jobs, isEmpty);
    expect(expanded.value, isFalse);
    expect(find.byType(InkWell), findsNothing);
    await finish(tester);
  });

  testWidgets('a job that went well leaves the bar at once', (tester) async {
    await pump(tester);
    final gate = Completer<void>();
    add(gate).ignore();
    await settle(tester);
    gate.complete();
    await settle(tester);
    await settle(tester);

    expect(find.byType(InkWell), findsNothing);
    await finish(tester);
  });

  testWidgets('slides in and back out rather than popping', (tester) async {
    await pump(tester);
    final gate = Completer<void>();
    add(gate).ignore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final midway = tester.getSize(find.byType(SizeTransition).first).height;
    expect(midway, greaterThan(0));
    expect(midway, lessThan(TransferBar.height));

    gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(InkWell), findsOneWidget, reason: 'still leaving');

    await settle(tester);
    expect(find.byType(InkWell), findsNothing);
    await finish(tester);
  });
}

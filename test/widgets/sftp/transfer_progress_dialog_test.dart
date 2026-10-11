import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/sftp/download_service.dart';
import 'package:termphin/widgets/sftp/transfer_progress_dialog.dart';

Widget _host(void Function(BuildContext context) onReady) {
  return TranslationProvider(
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => onReady(context),
            child: const Text('start'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the transferred size and per-file counter', (
    tester,
  ) async {
    late TransferSession session;
    await tester.pumpWidget(
      _host((context) {
        session = TransferSession(
          kind: TransferKind.download,
          initialLabel: 'report.pdf',
        )..show(context);
      }),
    );
    await tester.tap(find.text('start'));
    await tester.pump();

    session.update(
      const TransferProgress(
        label: 'report.pdf',
        itemIndex: 2,
        itemCount: 5,
        bytes: 512,
        totalBytes: 2048,
        fraction: 0.25,
      ),
    );
    await tester.pump();

    expect(find.text('25%'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.textContaining('2 of 5'), findsOneWidget);
    expect(find.textContaining('512 B of 2.0 KB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.25,
    );

    session.close();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('says what it is waiting for while the tree is listed', (
    tester,
  ) async {
    late TransferSession session;
    await tester.pumpWidget(
      _host((context) {
        session = TransferSession(
          kind: TransferKind.download,
          initialLabel: 'site',
        )..show(context);
      }),
    );
    await tester.tap(find.text('start'));
    await tester.pump();

    session.update(
      const TransferProgress(
        label: 'site',
        phase: TransferPhase.scanning,
        itemIndex: 12,
      ),
    );
    await tester.pump();

    expect(find.textContaining('Scanning folder'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    session.close();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('cancelling trips the token and closes the dialog at once', (
    tester,
  ) async {
    late TransferSession session;
    await tester.pumpWidget(
      _host((context) {
        session = TransferSession(
          kind: TransferKind.download,
          initialLabel: 'big.iso',
        )..show(context);
      }),
    );
    await tester.tap(find.text('start'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(session.isCancelled, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('closing removes its own route, not whatever is on top', (
    tester,
  ) async {
    late TransferSession session;
    late BuildContext hostContext;
    await tester.pumpWidget(
      _host((context) {
        hostContext = context;
        session = TransferSession(
          kind: TransferKind.download,
          initialLabel: 'report.pdf',
        )..show(context);
      }),
    );
    await tester.tap(find.text('start'));
    await tester.pump(const Duration(milliseconds: 400));

    unawaited(
      showDialog<void>(
        context: hostContext,
        builder: (_) => const AlertDialog(content: Text('on top')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    session.close();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('on top'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

void main() {
  testWidgets('touch drag scrolls the application in the alternate buffer', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(maxLines: 1000);
    terminal.onOutput = output.add;

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TerminalView(terminal))),
    );

    terminal.write('\x1b[?1049h');
    await tester.pumpAndSettle();
    expect(terminal.isUsingAltBuffer, isTrue);

    await tester.drag(find.byType(TerminalView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(output, isNotEmpty);
  });

  testWidgets('a full screen app with mouse tracking owns the scroll', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(maxLines: 1000);
    terminal.onOutput = output.add;

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TerminalView(terminal))),
    );

    for (var i = 0; i < 200; i++) {
      terminal.write('line $i\r\n');
    }
    terminal.write('\x1b[?1002h\x1b[?1006h');
    await tester.pumpAndSettle();
    output.clear();

    await tester.drag(find.byType(TerminalView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(output.join(), contains('\x1b[<65;'));
  });

  testWidgets('wheel reports carry the row under the finger', (tester) async {
    final output = <String>[];
    final terminal = Terminal(maxLines: 1000);
    terminal.onOutput = output.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 200, width: double.infinity),
              Expanded(child: TerminalView(terminal)),
            ],
          ),
        ),
      ),
    );

    terminal.write('\x1b[?1049h\x1b[?1002h\x1b[?1006h');
    await tester.pumpAndSettle();
    output.clear();

    final terminalRect = tester.getRect(find.byType(TerminalView));
    final touch = Offset(terminalRect.left + 40, terminalRect.top + 40);
    await tester.dragFrom(touch, const Offset(0, -120));
    await tester.pumpAndSettle();

    final report = RegExp(r'\x1b\[<\d+;(\d+);(\d+)M').firstMatch(output.join());
    expect(report, isNotNull);
    final reportedRow = int.parse(report!.group(2)!);
    expect(reportedRow, lessThan(6));
  });

  testWidgets('TerminalPane forwards alt buffer scroll to the app', (
    tester,
  ) async {
    final outputStream = StreamController<Uint8List>();
    final input = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalPane(
            outputStream: outputStream.stream,
            onInput: input.addAll,
            onResize: (_, _) {},
          ),
        ),
      ),
    );

    outputStream.add(Uint8List.fromList(utf8.encode('\x1b[?1049h')));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(TerminalPane), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(input, isNotEmpty);
    await outputStream.close();
  });

  testWidgets('a slow finger drag also reaches the app', (tester) async {
    final outputStream = StreamController<Uint8List>();
    final input = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalPane(
            outputStream: outputStream.stream,
            onInput: input.addAll,
            onResize: (_, _) {},
          ),
        ),
      ),
    );

    outputStream.add(Uint8List.fromList(utf8.encode('\x1b[?1049h')));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(TerminalPane));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(input, isNotEmpty);
    await outputStream.close();
  });
}

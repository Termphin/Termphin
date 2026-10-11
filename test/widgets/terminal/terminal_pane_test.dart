import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pinch zoom resizes the terminal only when the gesture ends', (
    tester,
  ) async {
    final output = StreamController<Uint8List>();
    addTearDown(output.close);
    final sizes = <(int, int)>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: TerminalPane(
            outputStream: output.stream,
            onInput: (_) {},
            onResize: (cols, rows) => sizes.add((cols, rows)),
          ),
        ),
      ),
    );
    await tester.pump();

    final initialResizeCount = sizes.length;
    final center = tester.getCenter(find.byType(TerminalPane));
    final first = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await tester.pump();

    await first.moveTo(center - const Offset(50, 0));
    await tester.pump();
    await second.moveTo(center + const Offset(50, 0));
    await tester.pump();

    expect(sizes, hasLength(initialResizeCount));

    await first.up();
    await second.up();
    await tester.pump();

    expect(sizes, hasLength(initialResizeCount + 1));
  });

  group('OSC 52', () {
    late List<String?> clipboardWrites;
    late StreamController<Uint8List> output;

    setUp(() async {
      clipboardWrites = [];
      output = StreamController<Uint8List>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardWrites.add(call.arguments['text'] as String?);
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await output.close();
    });

    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

    String osc52(String text) =>
        '\x1b]52;c;${base64.encode(utf8.encode(text))}\x07';

    Future<void> mount(WidgetTester tester, {Uint8List? history}) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            outputStream: output.stream,
            onInput: (_) {},
            onResize: (_, _) {},
            initialHistory: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> feed(WidgetTester tester, String sequence) async {
      await mount(tester);
      output.add(bytes(sequence));
      await tester.pumpAndSettle();
    }

    testWidgets('a write from the remote host reaches the clipboard', (
      tester,
    ) async {
      await feed(tester, osc52('hello from the server'));

      expect(clipboardWrites, ['hello from the server']);
      expect(
        find.text(AppLocale.en.buildSync().terminal.remoteCopied),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a read request is refused', (tester) async {
      await feed(tester, '\x1b]52;c;?\x07');

      expect(clipboardWrites, isEmpty);
    });

    testWidgets('a malformed payload is ignored', (tester) async {
      await feed(tester, '\x1b]52;c;not base64!!\x07');

      expect(clipboardWrites, isEmpty);
    });

    testWidgets('replayed scrollback does not copy again', (tester) async {
      await mount(
        tester,
        history: bytes('a log line\r\n${osc52('copied an hour ago')}done\r\n'),
      );

      expect(clipboardWrites, isEmpty);
      expect(
        find.text(AppLocale.en.buildSync().terminal.remoteCopied),
        findsNothing,
      );
    });

    testWidgets('a live copy right behind the replay still lands', (
      tester,
    ) async {
      await mount(tester, history: bytes('${osc52('old')}scrollback\r\n'));
      output.add(bytes(osc52('new')));
      await tester.pumpAndSettle();

      expect(clipboardWrites, ['new']);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a replay larger than one drain slice stays suppressed', (
      tester,
    ) async {
      final padding = 'x' * 20000;
      await mount(tester, history: bytes('$padding${osc52('old')}$padding'));

      expect(clipboardWrites, isEmpty);
    });
  });

  group('keyboard tap-to-dismiss', () {
    late StreamController<Uint8List> output;

    setUp(() {
      output = StreamController<Uint8List>();
    });

    tearDown(() async {
      await output.close();
    });

    testWidgets('tapping terminal when keyboard is open blurs and unfocuses', (
      tester,
    ) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            outputStream: output.stream,
            onInput: (_) {},
            onResize: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final focusNode = terminalView.focusNode!;

      await tester.tap(find.byType(TerminalPane));
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() => tester.view.resetViewInsets());
      await tester.pump();

      await tester.tap(find.byType(TerminalPane));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isFalse);

      tester.view.resetViewInsets();
      await tester.pump();

      await tester.tap(find.byType(TerminalPane));
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets(
      'drag gesture when keyboard is open does not dismiss keyboard',
      (tester) async {
        await pumpTestApp(
          tester,
          Scaffold(
            body: TerminalPane(
              outputStream: output.stream,
              onInput: (_) {},
              onResize: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final terminalView = tester.widget<TerminalView>(
          find.byType(TerminalView),
        );
        final focusNode = terminalView.focusNode!;

        await tester.tap(find.byType(TerminalPane));
        await tester.pumpAndSettle();
        expect(focusNode.hasFocus, isTrue);

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(() => tester.view.resetViewInsets());
        await tester.pump();

        await tester.drag(find.byType(TerminalPane), const Offset(0, -50));
        await tester.pumpAndSettle();

        expect(focusNode.hasFocus, isTrue);

        await tester.pump(const Duration(milliseconds: 350));
      },
    );
  });

  group('tapping and the keyboard', () {
    late StreamController<Uint8List> output;
    late List<String> links;

    setUp(() {
      output = StreamController<Uint8List>();
      links = [];
    });

    tearDown(() => output.close());

    Future<FocusNode> mount(WidgetTester tester, String text) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            outputStream: output.stream,
            onInput: (_) {},
            onResize: (_, _) {},
            onLinkDetected: (url, _) => links.add(url),
          ),
        ),
      );
      await tester.pumpAndSettle();
      output.add(Uint8List.fromList(utf8.encode(text)));
      await tester.pumpAndSettle();
      return tester.widget<TerminalView>(find.byType(TerminalView)).focusNode!;
    }

    ScrollPosition scroll(WidgetTester tester) => tester
        .widget<TerminalView>(find.byType(TerminalView))
        .scrollController!
        .position;

    /// Where [row]'s first cell is drawn, a few cells in.
    Offset cellAt(WidgetTester tester, int row) {
      final render = tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal;
      return render.localToGlobal(
        render.getOffset(CellOffset(3, row)) +
            Offset(render.cellSize.width / 2, render.cellSize.height / 2),
      );
    }

    testWidgets('a link opens its preview without raising the keyboard', (
      tester,
    ) async {
      final focus = await mount(tester, 'see https://termphin.dev here\r\n');

      await tester.tapAt(cellAt(tester, 0) + const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(links, ['https://termphin.dev']);
      expect(focus.hasFocus, isFalse);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.tapAt(cellAt(tester, 1));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('a link is underlined, plain text is not', (tester) async {
      await mount(tester, 'plain text only\r\n');
      final render = tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal;
      expect(render, isNot(paints..line()));

      output.add(
        Uint8List.fromList(utf8.encode('see https://termphin.dev here\r\n')),
      );
      await tester.pumpAndSettle();
      final from = render.getOffset(const CellOffset(4, 1));
      final to = render.getOffset(const CellOffset(24, 1));
      final y = from.dy + render.lineHeight - 1.5;
      expect(
        render,
        paints..line(p1: Offset(from.dx, y), p2: Offset(to.dx, y)),
      );
    });

    testWidgets('a link tapped with the keyboard up leaves it up', (
      tester,
    ) async {
      final focus = await mount(tester, 'see https://termphin.dev here\r\n');
      await tester.tapAt(cellAt(tester, 1));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() => tester.view.resetViewInsets());
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tapAt(cellAt(tester, 0) + const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(links, ['https://termphin.dev']);
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets(
      'raising the keyboard from the scrollback jumps to the prompt',
      (tester) async {
        final focus = await mount(
          tester,
          [for (var i = 0; i < 300; i++) 'line $i\r\n'].join(),
        );
        final position = scroll(tester);
        position.jumpTo(0);
        await tester.pump();

        await tester.tap(find.byType(TerminalPane));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);

        for (final inset in [100.0, 200.0, 300.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
        }
        addTearDown(() => tester.view.resetViewInsets());
        await tester.pumpAndSettle();

        final after = scroll(tester);
        expect(after.pixels, closeTo(after.maxScrollExtent, 1));
        await tester.pump(const Duration(milliseconds: 350));
      },
    );

    testWidgets('the prompt stays in view while the keyboard comes up', (
      tester,
    ) async {
      final focus = await mount(
        tester,
        [for (var i = 0; i < 300; i++) 'line $i\r\n'].join(),
      );

      await tester.tap(find.byType(TerminalPane));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);

      for (final inset in [100.0, 200.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        final position = scroll(tester);
        expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      }
      addTearDown(() => tester.view.resetViewInsets());
      await tester.pump(const Duration(milliseconds: 350));
    });
  });

  group('search', () {
    late StreamController<Uint8List> output;
    late TerminalPaneController controller;
    final t = AppLocale.en.buildSync();

    setUp(() {
      output = StreamController<Uint8List>();
      controller = TerminalPaneController();
    });

    tearDown(() => output.close());

    Future<void> mount(WidgetTester tester, String text) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            outputStream: output.stream,
            onInput: (_) {},
            onResize: (_, _) {},
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      output.add(Uint8List.fromList(utf8.encode(text)));
      await tester.pumpAndSettle();
    }

    List<TerminalHighlight> highlights(WidgetTester tester) => tester
        .widget<TerminalView>(find.byType(TerminalView))
        .controller!
        .highlights;

    ScrollPosition scroll(WidgetTester tester) => tester
        .widget<TerminalView>(find.byType(TerminalView))
        .scrollController!
        .position;

    Future<void> search(WidgetTester tester, String query) async {
      controller.openSearch();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
    }

    testWidgets('focuses the newest match and steps back to older ones', (
      tester,
    ) async {
      final lines = [
        'needle at the top',
        for (var i = 0; i < 200; i++) 'line $i',
        'needle at the bottom',
      ];
      await mount(tester, '${lines.join('\r\n')}\r\n');

      await search(tester, 'needle');

      expect(find.text('2/2'), findsOneWidget);
      expect(highlights(tester), hasLength(3));

      await tester.tap(find.byTooltip(t.terminalSearch.older));
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
      expect(scroll(tester).pixels, 0);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await mount(tester, 'hello\r\n');

      await search(tester, 'absent');

      expect(find.text(t.terminalSearch.noMatches), findsOneWidget);
      expect(highlights(tester), isEmpty);
    });

    testWidgets('counts output that arrives while the bar is open', (
      tester,
    ) async {
      await mount(tester, 'error one\r\n');
      await search(tester, 'error');
      expect(find.text('1/1'), findsOneWidget);

      output.add(Uint8List.fromList(utf8.encode('error two\r\n')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('closing removes the bar and every highlight', (tester) async {
      await mount(tester, 'error\r\n');
      await search(tester, 'error');

      await tester.tap(find.byTooltip(t.terminalSearch.close));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(highlights(tester), isEmpty);
    });
  });
}

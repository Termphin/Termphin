import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/app/app_commands.dart';
import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/services/terminal/session_terminal.dart';
import 'package:termphin/services/terminal/terminal_text.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';
import 'package:termphin/widgets/terminal/terminal_search_bar.dart';

import '../../support/session_terminal.dart';
import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pane that comes back finds the session as it now stands, '
      'scrolled to its end', (tester) async {
    final terminal = SessionTerminal();
    final sent = <String>[];
    Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
    Future<void> mount() async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            terminal: terminal,
            onInput: (input) => sent.add(utf8.decode(input)),
            onResize: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount();
    terminal.add(bytes('seen before leaving\r\n'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    final awayReplies = <String>[];
    terminal.onReply = awayReplies.add;
    terminal.add(
      bytes([for (var i = 0; i < 200; i++) 'while away $i\r\n'].join()),
    );
    terminal.add(bytes('\x1b[5n'));
    await tester.pumpAndSettle();

    await mount();
    terminal.add(bytes('\x1b[5n'));
    await tester.pumpAndSettle();

    final shown = terminalBufferText(terminal.terminal.buffer).split('\n');
    expect(shown.first, 'seen before leaving');
    expect(shown.last, 'while away 199');
    final position = tester
        .widget<TerminalView>(find.byType(TerminalView))
        .scrollController!
        .position;
    expect(position.pixels, position.maxScrollExtent);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(awayReplies, ['\x1b[0n']);
    expect(sent, ['\x1b[0n']);
  });

  testWidgets('a pane watching another device keeps that device\'s size, '
      'and follows its own again once it holds the session', (tester) async {
    final terminal = SessionTerminal();
    final resizes = <(int, int)>[];
    Future<void> mount(({int columns, int rows})? fixed) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            terminal: terminal,
            fixedSize: fixed,
            onInput: (_) {},
            onResize: (cols, rows) => resizes.add((cols, rows)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(null);
    final own = (terminal.terminal.viewWidth, terminal.terminal.viewHeight);
    expect(own, isNot((217, 61)));

    await mount((columns: 217, rows: 61));
    expect(
      (terminal.terminal.viewWidth, terminal.terminal.viewHeight),
      (217, 61),
    );
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).readOnly,
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await mount(null);
    expect((terminal.terminal.viewWidth, terminal.terminal.viewHeight), own);
  });

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
            terminal: terminalFedBy(output.stream),
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

  testWidgets(
    'a long press that selects holds off the tab swipe until it lifts',
    (tester) async {
      final output = StreamController<Uint8List>();
      addTearDown(output.close);
      addTearDown(() => terminalSelectionDragActive.value = false);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 600,
            child: TerminalPane(
              terminal: terminalFedBy(output.stream),
              onInput: (_) {},
              onResize: (_, _) {},
            ),
          ),
        ),
      );
      output.add(utf8.encode('hello world'));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(TerminalPane));
      final gesture = await tester.startGesture(origin + const Offset(12, 8));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(terminalSelectionDragActive.value, isTrue);

      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(terminalSelectionDragActive.value, isTrue);

      await gesture.up();
      await tester.pump();
      expect(terminalSelectionDragActive.value, isFalse);
    },
  );

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
            terminal: terminalFedBy(output.stream, replay: history),
            onInput: (_) {},
            onResize: (_, _) {},
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
            terminal: terminalFedBy(output.stream),
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
              terminal: terminalFedBy(output.stream),
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

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await terminalSettings.load();
      output = StreamController<Uint8List>();
      links = [];
    });

    tearDown(() => output.close());

    Future<FocusNode> mount(
      WidgetTester tester,
      String text, {
      void Function(List<int>)? onInput,
    }) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            terminal: terminalFedBy(output.stream),
            onInput: onInput ?? (_) {},
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

    testWidgets(
      'mouse reporting forwards the tap without raising the keyboard',
      (tester) async {
        final sent = <String>[];
        final focus = await mount(
          tester,
          '\x1b[?1000h\x1b[?1006hTUI button\r\n',
          onInput: (bytes) => sent.add(utf8.decode(bytes)),
        );

        await tester.tapAt(cellAt(tester, 0));
        await tester.pumpAndSettle();

        expect(sent, ['\x1b[<0;4;1M', '\x1b[<0;4;1m']);
        expect(focus.hasFocus, isFalse);

        output.add(Uint8List.fromList(utf8.encode('\x1b[?1000l')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));

        await tester.tapAt(cellAt(tester, 0));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 350));
      },
    );

    testWidgets('mouse reporting leaves an open keyboard up on tap', (
      tester,
    ) async {
      final sent = <String>[];
      final focus = await mount(
        tester,
        'shell\r\n',
        onInput: (bytes) => sent.add(utf8.decode(bytes)),
      );

      await tester.tapAt(cellAt(tester, 0));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() => tester.view.resetViewInsets());
      await tester.pump(const Duration(milliseconds: 350));

      output.add(
        Uint8List.fromList(utf8.encode('\x1b[?1000h\x1b[?1006hTUI button\r\n')),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(cellAt(tester, 1));
      await tester.pumpAndSettle();

      expect(sent, containsAllInOrder(['\x1b[<0;4;2M', '\x1b[<0;4;2m']));
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets(
      'mouse reporting drops stale focus left when the soft keyboard was dismissed',
      (tester) async {
        final focus = await mount(tester, 'shell\r\n');

        await tester.tapAt(cellAt(tester, 0));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);

        output.add(
          Uint8List.fromList(
            utf8.encode('\x1b[?1000h\x1b[?1006hTUI button\r\n'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));

        await tester.tapAt(cellAt(tester, 1));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        await tester.pump(const Duration(milliseconds: 350));
      },
    );

    testWidgets('mouse reporting still raises the keyboard when guard is off', (
      tester,
    ) async {
      await terminalSettings.mouseKeyboardGuard.set(false);
      final focus = await mount(tester, '\x1b[?1000h\x1b[?1006hTUI button\r\n');

      await tester.tapAt(cellAt(tester, 0));
      await tester.pumpAndSettle();

      expect(focus.hasFocus, isTrue);
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
            terminal: terminalFedBy(output.stream),
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

    testWidgets('the bar stands above the terminal, not over its first rows', (
      tester,
    ) async {
      await mount(tester, 'hello\r\n');
      final terminalBefore = tester.getRect(find.byType(TerminalView));

      controller.openSearch();
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(TerminalSearchBar));
      final terminal = tester.getRect(find.byType(TerminalView));
      expect(bar.height, kTerminalSearchBarHeight);
      expect(bar.top, terminalBefore.top);
      expect(terminal.top, greaterThanOrEqualTo(bar.bottom));
      expect(terminal.bottom, terminalBefore.bottom);
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

  group('desktop clipboard keys', () {
    late List<String?> clipboardWrites;
    late List<String> sent;
    late StreamController<Uint8List> output;

    setUp(() {
      clipboardWrites = [];
      sent = [];
      output = StreamController<Uint8List>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardWrites.add(call.arguments['text'] as String?);
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': 'pasted'};
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await output.close();
    });

    Future<void> mount(
      WidgetTester tester, {
      FocusOnKeyEventCallback? onKeyEvent,
    }) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: TerminalPane(
            terminal: terminalFedBy(output.stream),
            onInput: (bytes) => sent.add(utf8.decode(bytes)),
            onResize: (_, _) {},
            onKeyEvent: onKeyEvent,
          ),
        ),
      );
      await tester.pumpAndSettle();
      output.add(Uint8List.fromList(utf8.encode('hello world')));
      await tester.pumpAndSettle();
    }

    Future<void> dragAcrossFirstLine(WidgetTester tester) async {
      final origin = tester.getTopLeft(find.byType(TerminalPane));
      final gesture = await tester.startGesture(
        origin + const Offset(24, 8),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(origin + const Offset(60, 8));
      await gesture.moveTo(origin + const Offset(100, 8));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> focusTerminal(WidgetTester tester) async {
      await tester.tapAt(
        tester.getCenter(find.byType(TerminalPane)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an app shortcut never reaches the shell, the bare key '
        'does', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      AppCommands.instance.install();
      addTearDown(AppCommands.instance.uninstall);
      await mount(tester);
      await focusTerminal(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(sent, ['\x1b[6~']);
      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a key onKeyEvent handles is kept from the shell', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(
        tester,
        onKeyEvent: (_, event) => event.logicalKey == LogicalKeyboardKey.escape
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
      );
      await focusTerminal(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(sent, ['\t']);
      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('a selection dragged out first is copied by Ctrl+C', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(tester);

      await dragAcrossFirstLine(tester);
      await pressCtrl(tester, LogicalKeyboardKey.keyC);

      expect(clipboardWrites, hasLength(1));
      expect(clipboardWrites.single, isNotEmpty);
      expect(sent, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> middleClick(WidgetTester tester) async {
      await tester.tapAt(
        tester.getCenter(find.byType(TerminalPane)),
        kind: PointerDeviceKind.mouse,
        buttons: kTertiaryButton,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the middle button pastes the selection, as on Linux', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(tester);
      await dragAcrossFirstLine(tester);

      await middleClick(tester);

      expect(sent, hasLength(1));
      expect(sent.single, isNot('pasted'));
      expect('hello world', contains(sent.single));
      expect(find.text(t.contextMenu.paste), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the middle button pastes the clipboard with no selection', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(tester);

      await middleClick(tester);

      expect(sent, ['pasted']);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('select all copies the lines with text, not the empty screen', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(tester);
      await focusTerminal(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboardWrites.last, 'hello world');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Ctrl+V pastes after a click that cleared a selection', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(tester);
      await dragAcrossFirstLine(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getCenter(find.byType(TerminalPane)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await pressCtrl(tester, LogicalKeyboardKey.keyV);

      expect(sent, ['pasted']);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('watching zoom and pan', () {
    late SessionTerminal terminal;
    late TerminalPaneController controller;
    late List<double> fontChanges;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await terminalSettings.load();
      terminal = SessionTerminal();
      controller = TerminalPaneController();
      fontChanges = [];
    });

    Future<void> mountWatching(
      WidgetTester tester, {
      ({int columns, int rows})? fixedSize = const (columns: 200, rows: 100),
      Size paneSize = const Size(400, 500),
    }) async {
      await pumpTestApp(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: paneSize.width,
              height: paneSize.height,
              child: TerminalPane(
                terminal: terminal,
                fixedSize: fixedSize,
                controller: controller,
                onInput: (_) {},
                onResize: (_, _) {},
                onFontSizeChanged: fontChanges.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect renderedViewRect(WidgetTester tester) {
      final finder = find.byType(TerminalView);
      return Rect.fromPoints(
        tester.getTopLeft(finder),
        tester.getBottomRight(finder),
      );
    }

    double renderedFontSize(WidgetTester tester) => tester
        .widget<TerminalView>(find.byType(TerminalView))
        .textStyle
        .fontSize;

    Future<void> pinch(
      WidgetTester tester, {
      required Offset center,
      required double startHalfSpan,
      required double endHalfSpan,
    }) async {
      final first = await tester.startGesture(
        center - Offset(startHalfSpan, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + Offset(startHalfSpan, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - Offset(endHalfSpan, 0));
      await second.moveTo(center + Offset(endHalfSpan, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
    }

    Future<void> doubleTapAt(WidgetTester tester, Offset pos) async {
      await tester.tapAt(pos);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(pos);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a watching pane starts fitted: the rendered grid is no larger than the pane',
      (tester) async {
        await mountWatching(tester);

        final pane = tester.getRect(find.byType(TerminalPane));
        final grid = renderedViewRect(tester);

        expect(grid.width, lessThanOrEqualTo(pane.width + 0.5));
        expect(grid.height, lessThanOrEqualTo(pane.height + 0.5));
      },
    );

    testWidgets(
      'a pinch while watching zooms the view (rendered grid grows) and never calls onFontSizeChanged',
      (tester) async {
        await mountWatching(tester);
        final initialGrid = renderedViewRect(tester);
        final initialFont = renderedFontSize(tester);

        await pinch(
          tester,
          center: tester.getCenter(find.byType(TerminalPane)),
          startHalfSpan: 20,
          endHalfSpan: 100,
        );

        final zoomedGrid = renderedViewRect(tester);
        expect(zoomedGrid.width, greaterThan(initialGrid.width));
        expect(renderedFontSize(tester), greaterThan(initialFont));
        expect(fontChanges, isEmpty);
      },
    );

    testWidgets('zoom is clamped to [fitted, 2x]', (tester) async {
      await mountWatching(tester);
      final pane = tester.getRect(find.byType(TerminalPane));
      final fittedGrid = renderedViewRect(tester);
      final fittedFont = renderedFontSize(tester);
      final center = pane.center;

      await pinch(tester, center: center, startHalfSpan: 100, endHalfSpan: 10);
      expect(renderedViewRect(tester).width, closeTo(fittedGrid.width, 0.5));
      expect(renderedFontSize(tester), closeTo(fittedFont, 0.05));

      for (var i = 0; i < 4; i++) {
        await pinch(
          tester,
          center: center,
          startHalfSpan: 10,
          endHalfSpan: 150,
        );
      }
      expect(renderedFontSize(tester), closeTo(24.0, 0.05));
      expect(fontChanges, isEmpty);
    });

    testWidgets(
      'double-tap zooms in, a second double-tap goes back to fitted',
      (tester) async {
        await mountWatching(tester);
        final pane = tester.getRect(find.byType(TerminalPane));
        final fittedGrid = renderedViewRect(tester);

        await doubleTapAt(tester, pane.topLeft + const Offset(100, 80));
        final zoomedGrid = renderedViewRect(tester);
        expect(zoomedGrid.width, greaterThan(pane.width));
        expect(renderedFontSize(tester), closeTo(12.0, 0.05));

        await doubleTapAt(tester, pane.center);
        final restoredGrid = renderedViewRect(tester);
        expect(restoredGrid.width, closeTo(fittedGrid.width, 0.5));
        expect(restoredGrid.topLeft, pane.topLeft);
      },
    );

    testWidgets(
      'at fitted zoom drag scrolls scrollback and long-press selects; while zoomed in one-finger drag pans and terminal does not get the drag',
      (tester) async {
        await mountWatching(tester);
        terminal.add(
          Uint8List.fromList(
            utf8.encode([for (var i = 0; i < 250; i++) 'line $i\r\n'].join()),
          ),
        );
        await tester.pumpAndSettle();

        final scrollPosition = tester
            .widget<TerminalView>(find.byType(TerminalView))
            .scrollController!
            .position;
        final bottomPixels = scrollPosition.pixels;
        expect(bottomPixels, greaterThan(0));

        final fittedGrid = renderedViewRect(tester);
        await tester.dragFrom(fittedGrid.center, const Offset(0, 60));
        await tester.pumpAndSettle();
        expect(scrollPosition.pixels, lessThan(bottomPixels));

        await tester.longPressAt(fittedGrid.topLeft + const Offset(16, 12));
        await tester.pumpAndSettle();
        expect(await controller.getSelectedText(), isNotNull);

        final scrolledPixels = scrollPosition.pixels;
        final pane = tester.getRect(find.byType(TerminalPane));
        await doubleTapAt(tester, fittedGrid.center);
        final gridBeforePan = renderedViewRect(tester);

        await tester.dragFrom(pane.center, const Offset(-80, -40));
        await tester.pumpAndSettle();

        final gridAfterPan = renderedViewRect(tester);
        expect(gridAfterPan.topLeft.dx, lessThan(gridBeforePan.topLeft.dx));
        expect(scrollPosition.pixels, scrolledPixels);
      },
    );

    testWidgets(
      'desktop Ctrl+wheel and PointerScaleEvent zoom around the pointer without changing saved font size',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await mountWatching(tester);
        final pane = tester.getRect(find.byType(TerminalPane));
        final initialWidth = renderedViewRect(tester).width;

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(pane.topLeft + const Offset(120, 60)),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        final afterWheelWidth = renderedViewRect(tester).width;
        expect(afterWheelWidth, greaterThan(initialWidth));
        expect(fontChanges, isEmpty);

        final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(
          trackpad.hover(pane.topLeft + const Offset(160, 80)),
        );
        await tester.sendEventToBinding(
          PointerScaleEvent(
            position: pane.topLeft + const Offset(160, 80),
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();

        expect(renderedViewRect(tester).width, greaterThan(afterWheelWidth));
        expect(fontChanges, isEmpty);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'when fixedSize changes, fitted zoom recomputes and current zoom is clamped',
      (tester) async {
        await mountWatching(tester, fixedSize: const (columns: 200, rows: 100));
        final pane = tester.getRect(find.byType(TerminalPane));
        final smallFont = renderedFontSize(tester);

        await mountWatching(tester, fixedSize: const (columns: 40, rows: 20));
        final widerFont = renderedFontSize(tester);
        expect(widerFont, greaterThan(smallFont));
        expect(
          renderedViewRect(tester).width,
          lessThanOrEqualTo(pane.width + 0.5),
        );
      },
    );

    testWidgets(
      'after fixedSize goes back to null the pane renders exactly like a normal pane (no leftover scale/offset)',
      (tester) async {
        await mountWatching(tester);
        final pane = tester.getRect(find.byType(TerminalPane));

        await doubleTapAt(tester, pane.center);
        await tester.drag(find.byType(TerminalPane), const Offset(-90, -50));
        await tester.pumpAndSettle();
        expect(renderedViewRect(tester).width, greaterThan(pane.width));

        await mountWatching(tester, fixedSize: null);

        final view = tester.widget<TerminalView>(find.byType(TerminalView));
        expect(view.autoResize, isTrue);
        expect(view.readOnly, isFalse);
        expect(view.textStyle.fontSize, 12.0);
        expect(renderedViewRect(tester), pane);
      },
    );

    testWidgets('the reveal-cell helper brings an off-screen cell into view', (
      tester,
    ) async {
      await mountWatching(tester);
      final pane = tester.getRect(find.byType(TerminalPane));

      await doubleTapAt(tester, pane.topLeft + const Offset(20, 20));
      await tester.pumpAndSettle();

      final render = tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal;
      Offset cellGlobalCenter(int col, int row) {
        final local =
            render.getOffset(CellOffset(col, row)) +
            Offset(render.cellSize.width / 2, render.cellSize.height / 2);
        return render.localToGlobal(local);
      }

      expect(pane.contains(cellGlobalCenter(180, 90)), isFalse);

      controller.revealWatchingCell(180, 90);
      await tester.pumpAndSettle();

      expect(pane.contains(cellGlobalCenter(180, 90)), isTrue);
    });

    testWidgets('zoomed in, a button zooms all the way out and the session '
        'swipe is held off until then', (tester) async {
      await mountWatching(tester);
      final pane = tester.getRect(find.byType(TerminalPane));
      final fittedGrid = renderedViewRect(tester);
      expect(find.byKey(const ValueKey('watchingFit')), findsNothing);
      expect(terminalWatchingZoomedIn.value, isFalse);

      await doubleTapAt(tester, pane.topLeft + const Offset(100, 80));
      await tester.pump();
      expect(terminalWatchingZoomedIn.value, isTrue);

      await tester.tap(find.byKey(const ValueKey('watchingFit')));
      await tester.pumpAndSettle();
      expect(renderedViewRect(tester).width, closeTo(fittedGrid.width, 0.5));
      expect(find.byKey(const ValueKey('watchingFit')), findsNothing);
      expect(terminalWatchingZoomedIn.value, isFalse);
    });

    testWidgets('a pane gone while zoomed in does not hold the swipe off', (
      tester,
    ) async {
      await mountWatching(tester);
      final pane = tester.getRect(find.byType(TerminalPane));
      await doubleTapAt(tester, pane.topLeft + const Offset(100, 80));
      await tester.pump();
      expect(terminalWatchingZoomedIn.value, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(terminalWatchingZoomedIn.value, isFalse);
    });

    testWidgets('the holder\'s cursor wears a badge while it is shown', (
      tester,
    ) async {
      await mountWatching(tester);
      terminal.add(Uint8List.fromList(utf8.encode('\$ ls')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('holderCursor')), findsOneWidget);

      terminal.add(Uint8List.fromList(utf8.encode('\x1b[?25l')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('holderCursor')), findsNothing);

      terminal.add(Uint8List.fromList(utf8.encode('\x1b[?25h')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('holderCursor')), findsOneWidget);

      await mountWatching(tester, fixedSize: null);
      expect(find.byKey(const ValueKey('holderCursor')), findsNothing);
    });
  });
}

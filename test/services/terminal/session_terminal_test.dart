import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/terminal/session_terminal.dart';
import 'package:termphin/services/terminal/terminal_text.dart';

void main() {
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  String shownBy(SessionTerminal session) =>
      terminalBufferText(session.terminal.buffer);

  const cursorPositionQuery = '\x1b[6n';

  test('starts at the size the pty was opened with', () {
    final session = SessionTerminal(columns: 132, rows: 50);

    expect(session.terminal.viewWidth, 132);
    expect(session.terminal.viewHeight, 50);
  });

  test('parses queued output without being asked to', () async {
    final session = SessionTerminal()..add(bytes('hello'));

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(shownBy(session), 'hello');
  });

  group('parsing time is shared', () {
    final scheduler = TerminalParseScheduler.instance;

    tearDown(() => scheduler.refreshRateOverride = null);

    Future<void> untilIdle(List<SessionTerminal> sessions) async {
      for (var waited = 0; waited < 400; waited++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final lengths = [for (final s in sessions) shownBy(s).length];
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final later = [for (final s in sessions) shownBy(s).length];
        if (lengths.join() == later.join()) return;
      }
    }

    test('a turn is a third of a frame, within reason', () {
      scheduler.refreshRateOverride = 120;
      expect(scheduler.slice, const Duration(microseconds: 2500));
      scheduler.refreshRateOverride = 60;
      expect(scheduler.slice, const Duration(microseconds: 5000));
      scheduler.refreshRateOverride = 1000;
      expect(scheduler.slice, const Duration(microseconds: 1500));
      scheduler.refreshRateOverride = 10;
      expect(scheduler.slice, const Duration(milliseconds: 6));
    });

    test('the terminal on screen is parsed at once, one nobody is looking '
        'at a frame later', () async {
      final unwatched = SessionTerminal()..add(bytes('unwatched'));
      await null;
      expect(shownBy(unwatched), isEmpty);

      final watched = SessionTerminal()
        ..bind(Object(), onOutput: (_) {}, onResize: (_, _) {})
        ..add(bytes('watched'));
      await null;
      expect(shownBy(watched), 'watched');

      await untilIdle([unwatched]);
      expect(shownBy(unwatched), 'unwatched');
    });

    test(
      'a pane arriving finds what was still queued parsed at once',
      () async {
        final session = SessionTerminal()..add(bytes('queued'));

        session.bind(Object(), onOutput: (_) {}, onResize: (_, _) {});
        await null;

        expect(shownBy(session), 'queued');
      },
    );

    test('a terminal too far behind stops waiting its turn', () async {
      final behind = SessionTerminal()..add(bytes('${'x' * 79}\r\n' * 14000));

      await null;

      expect(shownBy(behind), isNotEmpty);
    });

    test('a busy terminal on screen does not starve the rest', () async {
      scheduler.refreshRateOverride = 120;
      final line = '${'x' * 70}\r\n';
      final watched = SessionTerminal()
        ..bind(Object(), onOutput: (_) {}, onResize: (_, _) {})
        ..add(bytes(line * 6000));
      final unwatched = [
        for (var i = 0; i < 3; i++) SessionTerminal()..add(bytes(line * 500)),
      ];

      await untilIdle([watched, ...unwatched]);

      expect(shownBy(watched).split('\n'), hasLength(6000));
      for (final session in unwatched) {
        expect(shownBy(session).split('\n'), hasLength(500));
      }
    });
  });

  test('puts a character split across two chunks back together', () {
    final encoded = bytes('zażółć');
    final session = SessionTerminal()
      ..add(Uint8List.sublistView(encoded, 0, 3))
      ..add(Uint8List.sublistView(encoded, 3))
      ..flush();

    expect(shownBy(session), 'zażółć');
  });

  group('with no pane bound', () {
    test('answers the program itself', () {
      final replies = <String>[];
      SessionTerminal(onReply: replies.add)
        ..add(bytes('ab$cursorPositionQuery'))
        ..flush();

      expect(replies, ['\x1b[1;3R']);
    });

    test('does not answer a query that is part of a replay', () {
      final replies = <String>[];
      final session = SessionTerminal(
        replay: bytes('ab$cursorPositionQuery'),
        onReply: replies.add,
      )..flush();

      expect(replies, isEmpty);
      expect(session.replaying, isFalse);
    });

    test('answers live output queued right behind a replay', () {
      final replies = <String>[];
      SessionTerminal(replay: bytes('ab'), onReply: replies.add)
        ..add(bytes(cursorPositionQuery))
        ..flush();

      expect(replies, ['\x1b[1;3R']);
    });
  });

  group('a bound pane', () {
    test('takes the answers and the resizes, and gives them back', () {
      final replies = <String>[];
      final toPane = <String>[];
      final sizes = <(int, int)>[];
      final pane = Object();
      final session = SessionTerminal(onReply: replies.add)
        ..bind(
          pane,
          onOutput: toPane.add,
          onResize: (columns, rows) => sizes.add((columns, rows)),
        );

      session
        ..add(bytes(cursorPositionQuery))
        ..flush();
      session.terminal.resize(100, 30);
      session
        ..release(pane)
        ..add(bytes(cursorPositionQuery))
        ..flush();
      session.terminal.resize(90, 20);

      expect(toPane, ['\x1b[1;1R']);
      expect(sizes, [(100, 30)]);
      expect(replies, ['\x1b[1;1R']);
    });

    test('is not unbound by the pane it replaced leaving late', () {
      final toNewPane = <String>[];
      final oldPane = Object();
      final newPane = Object();
      final session = SessionTerminal()
        ..bind(oldPane, onOutput: (_) {}, onResize: (_, _) {})
        ..bind(newPane, onOutput: toNewPane.add, onResize: (_, _) {})
        ..release(oldPane);

      session
        ..add(bytes(cursorPositionQuery))
        ..flush();

      expect(toNewPane, ['\x1b[1;1R']);
    });

    test('hears of a layout that settles on the size it already has', () {
      final sizes = <(int, int)>[];
      final session = SessionTerminal(columns: 100, rows: 30)
        ..bind(
          Object(),
          onOutput: (_) {},
          onResize: (columns, rows) => sizes.add((columns, rows)),
        );

      session.terminal.resize(100, 30);

      expect(sizes, [(100, 30)]);
    });
  });

  test('a pane mounting at the same size leaves the program its scroll '
      'region', () {
    final session = SessionTerminal(columns: 20, rows: 10)
      ..add(bytes('\x1b[3;6r'))
      ..flush();
    final buffer = session.terminal.buffer;
    expect((buffer.marginTop, buffer.marginBottom), (2, 5));

    session.terminal.resize(20, 10);

    expect((buffer.marginTop, buffer.marginBottom), (2, 5));
  });

  test('a real resize still resets the scroll region', () {
    final session = SessionTerminal(columns: 20, rows: 10)
      ..add(bytes('\x1b[3;6r'))
      ..flush();

    session.terminal.resize(20, 12);

    final buffer = session.terminal.buffer;
    expect((buffer.marginTop, buffer.marginBottom), (0, 11));
  });

  test('a handler that throws does not leave what follows a replay taken '
      'for one', () {
    final replies = <String>[];
    final session = SessionTerminal(
      replay: bytes('a\x07'),
      onReply: replies.add,
    )..terminal.onBell = () => throw StateError('bell');

    expect(session.flush, throwsStateError);
    expect(session.replaying, isFalse);
    session
      ..terminal.onBell = null
      ..add(bytes(cursorPositionQuery))
      ..flush();

    expect(replies, hasLength(1));
  });

  test(
    'one terminal whose handler throws does not strand the others',
    () async {
      final failed = Completer<Object>();
      late SessionTerminal other;
      await runZonedGuarded(
        () async {
          SessionTerminal()
            ..bind(
              Object(),
              onOutput: (_) {},
              onResize: (_, _) {},
              onBell: () => throw StateError('bell'),
            )
            ..add(bytes('\x07'));
          other = SessionTerminal()
            ..bind(Object(), onOutput: (_) {}, onResize: (_, _) {})
            ..add(bytes('${'x' * 70}\r\n' * 4000));
          await Future<void>.delayed(const Duration(milliseconds: 600));
        },
        (error, stack) {
          if (!failed.isCompleted) failed.complete(error);
        },
      );

      expect(await failed.future, isStateError);
      expect(shownBy(other).split('\n'), hasLength(4000));
    },
  );

  test('a retired terminal takes nothing more', () {
    final session = SessionTerminal()
      ..add(bytes('kept'))
      ..flush()
      ..retire()
      ..add(bytes(' dropped'))
      ..flush();

    expect(shownBy(session), 'kept');
  });
}

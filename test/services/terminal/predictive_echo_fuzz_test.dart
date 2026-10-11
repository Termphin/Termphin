import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';
import 'package:termphin/services/terminal/predictive_echo.dart';

/// A line editor behind a `$ ` prompt, sending back the bytes a real shell
/// would, so predictions can be judged against the real thing. In [suggests]
/// mode it behaves like zsh with autosuggestions or fish: a grey completion
/// after the cursor, and the whole line redrawn on every key.
class _FakeShell {
  _FakeShell({required this.suggests});

  static const prompt = r'$ ';
  static const _known = ['ls -la /tmp', 'git status', 'cd projects', 'sudo x'];

  final bool suggests;
  final _line = <String>[];
  final _history = <String>[];
  var _pos = 0;
  var _commands = 0;
  var _password = false;
  var _fullScreen = false;
  var _fullScreenKeys = 0;

  String start() => prompt;

  int get length => _line.length;

  bool get readingPassword => _password || _fullScreen;

  String handle(String key) {
    if (_fullScreen) {
      if (key == 'q') {
        _fullScreen = false;
        return '\x1b[?1049l$prompt';
      }
      _fullScreenKeys++;
      return '\x1b[?2026h\x1b[12;1Hkeys: $_fullScreenKeys\x1b[1;1H\x1b[?2026l';
    }
    if (_password) {
      if (key != '\r') return '';
      _password = false;
      return '\r\nok\r\n$prompt';
    }
    if (key == '\r') {
      final command = _line.join();
      _line.clear();
      _pos = 0;
      if (command.isNotEmpty) _history.add(command);
      if (command.startsWith('z')) {
        _fullScreen = true;
        return '\r\n\x1b[?1049h\x1b[H\x1b[2Jfull screen\x1b[1;1H';
      }
      if (command.startsWith('sudo')) {
        _password = true;
        return '\x1b[K\r\nPassword: ';
      }
      final output = command.isEmpty
          ? ''
          : 'out${_commands++} ${command.length}\r\n';
      return '\x1b[K\r\n$output$prompt';
    }
    if (key == '\x03') {
      _line.clear();
      _pos = 0;
      return '^C\x1b[K\r\n$prompt';
    }
    if (key == '\x15') {
      _line.removeRange(0, _pos);
      _pos = 0;
      return _redraw();
    }
    if (key == '\x17') {
      var start = _pos;
      while (start > 0 && _line[start - 1] == ' ') {
        start--;
      }
      while (start > 0 && _line[start - 1] != ' ') {
        start--;
      }
      _line.removeRange(start, _pos);
      _pos = start;
      return _redraw();
    }
    if (key == '\x1b[A') {
      if (_history.isEmpty) return '\x07';
      _line
        ..clear()
        ..addAll(_history.last.split(''));
      _pos = _line.length;
      return _redraw();
    }
    if (key == '\t') return _insert('tab');
    if (key == '\x7f') {
      if (_pos == 0) return '\x07';
      _pos--;
      _line.removeAt(_pos);
      if (suggests) return _redraw();
      final rest = _line.sublist(_pos).join();
      return '\b$rest ${'\b' * (rest.length + 1)}';
    }
    if (key == '\x1b[D') {
      if (_pos == 0) return '\x07';
      _pos--;
      return '\b';
    }
    if (key == '\x1b[C') {
      if (_pos < _line.length) return _line[_pos++];
      final suggestion = _suggestion();
      if (suggestion.isEmpty) return '\x07';
      _line.addAll(suggestion.split(''));
      _pos = _line.length;
      return _redraw();
    }
    return _insert(key);
  }

  /// Output the server sends on its own, mid-typing: a job finishing.
  String notice() =>
      '\r\x1b[K[${_commands++}] Done\r\n$prompt${_line.join()}${_suffixText()}'
      '${_moveBack()}';

  String _insert(String text) {
    _line.insertAll(_pos, text.split(''));
    _pos += text.length;
    if (suggests) return _redraw();
    final rest = _line.sublist(_pos).join();
    return '$text$rest${'\b' * rest.length}';
  }

  String _suggestion() {
    if (!suggests || _line.isEmpty || _pos != _line.length) return '';
    final typed = _line.join();
    for (final known in _known) {
      if (known.length > typed.length && known.startsWith(typed)) {
        return known.substring(typed.length);
      }
    }
    return '';
  }

  String _suffixText() {
    final suggestion = _suggestion();
    return suggestion.isEmpty ? '' : '\x1b[90m$suggestion\x1b[0m';
  }

  String _moveBack() {
    final back = _line.length + _suggestion().length - _pos;
    return back > 0 ? '\x1b[${back}D' : '';
  }

  String _redraw() =>
      '\r\x1b[${prompt.length}C${_line.join()}${_suffixText()}\x1b[K'
      '${_moveBack()}';
}

class _Harness {
  _Harness(int seed)
    : random = Random(seed),
      shell = _FakeShell(suggests: seed.isOdd) {
    terminal = Terminal(maxLines: 10000)..resize(40, 12);
    oracle = Terminal(maxLines: 10000)..resize(40, 12);
    echo = PredictiveEcho(terminal)
      ..clock = (() => now)
      ..attach()
      ..enabled = true;
    final hello = shell.start();
    terminal.write(hello);
    oracle.write(hello);
    _snapshots.add(_Snapshot.of(oracle));
  }

  final Random random;
  final _FakeShell shell;
  var shownSteps = 0;
  late final Terminal terminal;
  late final Terminal oracle;
  late final PredictiveEcho echo;
  var now = 0;
  var _lastArrival = 0;

  /// Output on its way back, in order: a reply, or the acknowledgement of an
  /// input when the string is null.
  final _inFlight = <(int, String?, int)>[];
  var _seq = 0;

  /// The screen after each key, the first before any. The screen is only
  /// ever allowed to show one of these from the last one echoed onward.
  final _snapshots = <_Snapshot>[];
  var _delivered = 0;

  static const _letters = 'abcdexyzlsgituodq ';
  static const _editing = ['\x7f', '\x7f', '\x7f', '\x1b[D'];
  static const _other = [
    '\x1b[C',
    '\r',
    '\t',
    '\x03',
    '\x15',
    '\x17',
    '\x1b[A',
  ];

  /// Mostly letters, as typing is; some backspace, now and then anything.
  String _key() {
    final roll = random.nextInt(100);
    if (roll < 80) return _letters[random.nextInt(_letters.length)];
    if (roll < 93) return _editing[random.nextInt(_editing.length)];
    return _other[random.nextInt(_other.length)];
  }

  /// Keys whose result a person looks at before typing on.
  static bool _makesYouLook(String key) => _other.contains(key);

  /// A notice from the server is on its way. Until it lands, keys typed land
  /// somewhere nothing on the client can know about yet.
  bool get noticeInFlight => _noticesInFlight > 0;
  var _noticesInFlight = 0;

  String? lastKey;

  void type() {
    var key = _key();
    while (shell.length > 16 &&
        (key.length == 1 && key.codeUnitAt(0) >= 0x20 && key != '\x7f' ||
            key == '\t')) {
      key = _key();
    }
    lastKey = key;
    _seq++;
    echo.userInput(key, _seq);
    final reply = shell.handle(key);
    _send(reply, ack: _seq);
  }

  /// The server speaking up on its own while keys may be in flight.
  void notice() {
    if (shell.readingPassword) return;
    _noticesInFlight++;
    _send(shell.notice(), notice: true);
  }

  void _send(String reply, {int? ack, bool notice = false}) {
    oracle.write(reply);
    _snapshots.add(_Snapshot.of(oracle));
    final spike = random.nextInt(10) == 0;
    final latency = spike
        ? 400 + random.nextInt(1100)
        : 80 + random.nextInt(250);
    _lastArrival = max(_lastArrival, now + latency);
    if (ack != null) {
      _inFlight.add((_lastArrival, null, ack));
      _lastArrival += random.nextInt(40);
    }
    _inFlight.add((_lastArrival, reply, notice ? 1 : 0));
  }

  void _deliver((int, String?, int) item) {
    final (at, reply, ack) = item;
    now = max(now, at);
    if (reply == null) {
      echo.acknowledge(ack);
      return;
    }
    terminal.write(reply);
    _delivered++;
    if (ack == 1) _noticesInFlight--;
  }

  /// The engine's own timer, which fires every quarter second.
  var _nextTick = 250;

  void advance(int ms) {
    final until = now + ms;
    while (true) {
      final delivery = _inFlight.isNotEmpty && _inFlight.first.$1 <= until
          ? _inFlight.first.$1
          : null;
      final tick = _nextTick <= until ? _nextTick : null;
      if (delivery == null && tick == null) break;
      if (tick != null && (delivery == null || tick < delivery)) {
        now = max(now, tick);
        _nextTick += 250;
        echo.tick();
      } else {
        _deliver(_inFlight.removeAt(0));
      }
    }
    now = until;
  }

  void drain() {
    while (_inFlight.isNotEmpty) {
      _deliver(_inFlight.removeAt(0));
    }
  }

  /// What is on screen that no state the server passes through will show -
  /// something the prediction invented rather than merely showed early. The
  /// cursor may run ahead of the text (backspace moves it and leaves the
  /// character to the echo), never behind it.
  List<String> contradictions() {
    final cells = echo.cells;
    final cursor = echo.cursor;
    if (cells.isEmpty && cursor == null) return const [];

    int? firstFor(List<String> Function(_Snapshot) check, int from) {
      for (var j = from; j < _snapshots.length; j++) {
        if (check(_snapshots[j]).isEmpty) return j;
      }
      return null;
    }

    final textAt = firstFor(
      (s) => s.disagreements(terminal, cells, null),
      _delivered,
    );
    if (textAt == null) {
      return _snapshots.last.disagreements(terminal, cells, null);
    }
    if (cursor == null) return const [];
    final cursorAt = firstFor(
      (s) => s.disagreements(terminal, const [], cursor),
      textAt,
    );
    if (cursorAt == null) {
      return _snapshots.last.disagreements(terminal, const [], cursor);
    }
    return const [];
  }
}

class _Snapshot {
  _Snapshot(this.rows, this.scrollBack, this.cursor);

  factory _Snapshot.of(Terminal t) {
    final b = t.buffer;
    return _Snapshot(
      [
        for (var r = 0; r < t.viewHeight; r++)
          [
            for (var c = 0; c < t.viewWidth; c++)
              b.lines[b.scrollBack + r].getCodePoint(c),
          ],
      ],
      b.scrollBack,
      CellOffset(b.cursorX, b.cursorY),
    );
  }

  final List<List<int>> rows;
  final int scrollBack;
  final CellOffset cursor;

  List<String> disagreements(
    Terminal terminal,
    List<TerminalOverlayCell> cells,
    CellOffset? shownCursor,
  ) {
    final shift = scrollBack - terminal.buffer.scrollBack;
    final problems = <String>[];
    for (final c in cells) {
      final row = c.row - shift;
      if (row < 0 || row >= rows.length) continue;
      final shown = _char(c.cell.content & CellContent.codepointMask);
      final truth = _char(rows[row][c.column]);
      if (shown != truth) {
        problems.add('cell ${c.row}:${c.column} "$shown" vs "$truth"');
      }
    }
    if (shownCursor != null) {
      final truth = CellOffset(cursor.x, cursor.y + shift);
      if (shownCursor != truth) {
        problems.add('cursor $shownCursor vs $truth');
      }
    }
    return problems;
  }

  static String _char(int code) => code == 0 ? ' ' : String.fromCharCode(code);
}

void main() {
  for (var seed = 0; seed < 500; seed++) {
    test('seed $seed: nothing shown disagrees with the echo', () {
      final h = _Harness(seed);
      for (var step = 0; step < 300; step++) {
        final roll = h.random.nextInt(40);
        if (roll == 0) {
          h.notice();
        } else if (roll < 13) {
          h.advance(h.random.nextInt(roll < 3 ? 2000 : 200));
        } else {
          h.type();
          h.advance(
            _Harness._makesYouLook(h.lastKey!) && h.random.nextInt(5) > 0
                ? 300 + h.random.nextInt(1200)
                : 60 + h.random.nextInt(200),
          );
        }
        if (h.echo.cells.isNotEmpty) h.shownSteps++;
        if (h.noticeInFlight) continue;
        final problems = h.contradictions();
        expect(problems, isEmpty, reason: 'step $step');
      }

      expect(h.shownSteps, greaterThan(0), reason: 'never predicted anything');

      h.drain();
      h.now += 6000;
      h.echo.tick();
      expect(h.echo.cells, isEmpty, reason: 'left on screen after quiet');
      expect(h.echo.cursor, isNull, reason: 'cursor left after quiet');
    });
  }
}

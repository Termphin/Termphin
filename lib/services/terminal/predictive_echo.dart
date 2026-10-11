import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:terminal_view/terminal_view.dart';

/// Echo latency above which predictions are shown, and at or below which they
/// are hidden again once nothing is in flight. The gap is hysteresis, so a
/// link hovering around one number does not make them flicker.
const _kShowAboveMs = 60;
const _kHideAtOrBelowMs = 40;

/// Echo latency above which shown predictions are dimmed, and at or below
/// which they are drawn plainly again.
const _kDimAboveMs = 160;
const _kUndimAtOrBelowMs = 100;

/// A prediction still unanswered after this long is a glitch: predictions are
/// shown even on a link that is otherwise fast.
const _kGlitchMs = 250;

/// Unanswered after this long, predictions are dimmed as well.
const _kGlitchDimMs = 5000;

/// Quick confirmations needed to work a glitch off, and the least time between
/// two that count.
const _kGlitchRepairCount = 10;
const _kGlitchRepairIntervalMs = 150;

/// Unanswered after this long, a prediction is judged against the screen even
/// with no output to go by. Covers a session that died with keys in flight.
const _kGiveUpMs = 5000;

/// Floor on how long output may arrive without answering a prediction before
/// the prediction is judged. Generous on purpose: a prediction judged too soon
/// is taken off screen and put back by its own echo a moment later, which is
/// exactly the flicker this exists to avoid.
const _kMinSettleMs = 1000;

/// How long after the server acknowledges a key its echo may still be on the
/// way: the acknowledgement leaves sshd as soon as the key is handed to the
/// pty, and the program answers a moment later.
const _kEchoGraceMs = 120;

/// Latency assumed before the first measurement.
const _kInitialSrttMs = 1000.0;

/// Input longer than this is a paste, not typing, and is not predicted.
const _kMaxPredictedRunes = 32;

const _kTickInterval = Duration(milliseconds: _kGlitchMs);

/// Local echo of typed input, drawn before the server's echo arrives - the
/// technique mosh popularised.
///
/// Every byte sent to the program is fed to [userInput]. The engine keeps its
/// own idea of where the cursor is going to be once the server has caught up,
/// and predicts the few keys whose effect on a line editor is certain:
/// printable characters typed at the end of the text, and backspace and left
/// arrow within what was typed on this line. Output from the program is
/// compared against those predictions: a match confirms, a mismatch throws
/// them away. Nothing here ever writes to the buffer; predictions are only
/// drawn over it.
///
/// Any other key - Enter, Tab, a control key, right arrow - has an effect only
/// the server knows, so the engine stops predicting altogether until the
/// server has caught up with everything typed, and only then re-reads the
/// cursor from the screen. Reading it any earlier would read a screen that
/// keys still in flight are about to change.
///
/// Caught up is known, not guessed, when the embedder reports the server's
/// receipt of each input through [acknowledge] - the role mosh's acks play.
/// Without that it falls back on a stretch of quiet.
///
/// Predictions are grouped into epochs, and a new epoch stays hidden until one
/// of its predictions is confirmed. That is what keeps a password typed after
/// `sudo` off the screen: the server never echoes it, so its epoch is never
/// confirmed.
///
/// Shown only on a slow link, judged by how long the echo takes to come back.
///
/// Drawn as the terminal's [TerminalOverlay] and judged from
/// [Terminal.onAfterWrite]; [attach] claims both.
class PredictiveEcho implements TerminalOverlay {
  PredictiveEcho(this.terminal);

  final Terminal terminal;

  /// The buffer the program is drawing on right now.
  Buffer buffer() => terminal.buffer;

  /// Asks for a repaint - unless the program is holding a frame back, which
  /// would show it half drawn. The repaint that ends the hold draws this too.
  void onChanged() {
    if (!terminal.isHoldingFrame) terminal.notifyListeners();
  }

  void attach() {
    terminal.overlay = this;
    terminal.onAfterWrite = outputWritten;
  }

  /// Milliseconds on a monotonic clock.
  @visibleForTesting
  int Function() clock = _defaultClock;

  static final _stopwatch = Stopwatch()..start();

  static int _defaultClock() => _stopwatch.elapsedMilliseconds;

  bool _enabled = false;

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (!value) {
      _reset();
      _srttTrigger = false;
      _glitchTrigger = 0;
      _cancelTick();
      onChanged();
    }
  }

  final _rows = <BufferLine, List<_CellPrediction?>>{};

  /// Where the cursor will be once the server has processed every key sent.
  /// Null when that is simply wherever the screen shows it.
  _CursorPrediction? _cursor;

  /// A key went out whose effect cannot be predicted, so where the cursor is
  /// going is unknown until the server catches up.
  var _lost = false;

  var _lastInputAt = -1 << 40;

  /// The last input sent, and the last the server confirmed receiving; -1
  /// until the first confirmation, which is also what says one is coming.
  var _sent = 0;

  var _acked = -1;

  var _ackedAt = 0;

  /// Where typing on the current line started. Backspace and left arrow are
  /// only predicted to the right of it - never into the prompt.
  BufferLine? _inputLine;

  var _inputStart = 0;

  var _predictionEpoch = 1;

  var _confirmedEpoch = 0;

  double? _srtt;

  var _srttTrigger = false;

  var _dimmed = false;

  var _glitchTrigger = 0;

  var _lastQuickConfirmation = 0;

  var _lastWidth = -1;

  var _lastHeight = -1;

  Timer? _tick;

  /// Smoothed time from a keystroke to its echo, once one has been measured.
  double? get echoLatency => _srtt;

  /// Whether predictions are being drawn at all.
  bool get isShowing => _enabled && (_srttTrigger || _glitchTrigger > 0);

  @override
  bool get dimmed => isShowing && _dimmed;

  @override
  List<TerminalOverlayCell> get cells {
    if (!isShowing || _rows.isEmpty) return const [];
    final buffer = this.buffer();
    final result = <TerminalOverlayCell>[];
    for (final entry in _rows.entries) {
      final row = _screenRow(buffer, entry.key);
      if (row == null) continue;
      final cells = entry.value;
      for (var col = 0; col < cells.length; col++) {
        final p = cells[col];
        if (p == null || _isTentative(p.epoch)) continue;
        result.add(
          TerminalOverlayCell(
            row,
            col,
            CellData(
              foreground: p.foreground,
              background: p.background,
              flags: p.flags,
              content: p.codePoint | (1 << CellContent.widthShift),
            ),
          ),
        );
      }
    }
    return result;
  }

  @override
  CellOffset? get cursor {
    final cursor = _cursor;
    if (!isShowing || cursor == null || _isTentative(cursor.epoch)) {
      return null;
    }
    final row = _screenRow(buffer(), cursor.line);
    if (row == null) return null;
    return CellOffset(cursor.col, row);
  }

  /// Feeds bytes that were just sent to the program. [seq] numbers the input
  /// for [acknowledge]; it counts up on its own when not given.
  ///
  /// Culled before this input counts as sent: whether the server has caught
  /// up is a question about what came before it. Nothing is predicted in a
  /// full-screen program, but its keys are in flight all the same - the one
  /// that quits it lands the shell somewhere the screen does not show yet -
  /// so tracking is lost all the same.
  void userInput(String data, [int? seq]) {
    final buffer = this.buffer();
    if (_enabled && !buffer.isAltBuffer) _cull(buffer, fromOutput: false);
    _sent = seq ?? _sent + 1;
    _lastInputAt = clock();
    if (!_enabled) return;
    if (buffer.isAltBuffer) {
      _loseTrack();
      return;
    }

    final runes = data.runes.toList(growable: false);
    if (runes.length > _kMaxPredictedRunes) {
      _loseTrack();
    } else {
      _predict(buffer, runes);
    }

    _scheduleTick();
    onChanged();
  }

  /// The server has received every input up to [seq].
  void acknowledge(int seq) {
    if (seq <= _acked) return;
    _acked = seq;
    _ackedAt = clock();
  }

  /// Judges predictions against output that was just written to the buffer.
  void outputWritten() {
    if (!_enabled) return;
    final buffer = this.buffer();
    if (buffer.isAltBuffer) {
      if (_hasPredictions) _reset();
      return;
    }
    _cull(buffer, fromOutput: true);
  }

  /// Drops every prediction, for when the screen changed under them in a way
  /// comparison would not catch - a resize reflowing the lines.
  void reset() {
    if (_hasPredictions) _reset();
  }

  void dispose() {
    _cancelTick();
  }

  /// What the timer does, exposed so tests can drive it without waiting.
  ///
  /// A full-screen program has nothing predicted and nothing to wait for;
  /// the next key or output back on the main screen picks things up again.
  @visibleForTesting
  void tick() {
    _tick = null;
    if (!_enabled) return;
    final buffer = this.buffer();
    if (buffer.isAltBuffer) return;
    _cull(buffer, fromOutput: false);
    _scheduleTick();
    onChanged();
  }

  bool get _hasPredictions => _rows.isNotEmpty || _cursor != null || _lost;

  bool _isTentative(int epoch) => epoch > _confirmedEpoch;

  void _scheduleTick() {
    if (_tick != null || !_hasPredictions) return;
    _tick = Timer(_kTickInterval, tick);
  }

  void _cancelTick() {
    _tick?.cancel();
    _tick = null;
  }

  void _becomeTentative() {
    _predictionEpoch++;
  }

  /// Stops predicting until the server has caught up: the cursor is going
  /// somewhere only the server knows. Predictions already made stay, to be
  /// judged against the echo.
  void _loseTrack() {
    _lost = true;
    _cursor = null;
    _inputLine = null;
    _becomeTentative();
  }

  void _reset() {
    _rows.clear();
    _loseTrack();
  }

  void _killEpoch(int epoch) {
    for (final cells in _rows.values) {
      for (var i = 0; i < cells.length; i++) {
        final p = cells[i];
        if (p != null && p.epoch >= epoch) cells[i] = null;
      }
    }
    _rows.removeWhere((_, cells) => cells.every((p) => p == null));
    _loseTrack();
  }

  int? _screenRow(Buffer buffer, BufferLine line) {
    if (!line.attached) return null;
    final row = line.index - buffer.scrollBack;
    if (row < 0 || row >= buffer.viewHeight) return null;
    return row;
  }

  /// How long output may keep arriving without answering a prediction before
  /// the prediction is taken to have been processed and got wrong.
  int get _settleMs =>
      max(_kMinSettleMs, (4 * (_srtt ?? _kInitialSrttMs)).round());

  /// Judges every prediction against the current screen and timing, dropping
  /// what has been confirmed, contradicted or settled.
  ///
  /// Output arrives in the order input was sent, so a confirmed prediction
  /// means everything typed before it has been processed too. "Caught up" is
  /// quiet for as long as a late echo is waited for: the screen then shows
  /// the effect of every key sent. Keys are only predicted on the line the
  /// cursor is on, so once the program's cursor has left a line, everything
  /// typed there has been answered. A cell neither predicted nor there before
  /// is the program's answer and, unless it is blank (a redraw may be half
  /// done), disagreeing with it is a contradiction; a match is settled at
  /// once, credit or not, since the screen already shows it and keeping it
  /// any longer can only go stale. No predicted key leaves its row - the
  /// engine stops tracking at the end of a line and on Enter - so a program
  /// cursor on another row means it drew something unforeseen (a job
  /// finishing, a prompt redrawn) and every prediction is off. Once caught
  /// up, a shown cursor that disagrees with the real one was wrong on
  /// screen, so nothing shown is kept.
  void _cull(Buffer buffer, {required bool fromOutput}) {
    if (!_hasPredictions) {
      _updateTriggers();
      return;
    }

    if (buffer.viewWidth != _lastWidth || buffer.viewHeight != _lastHeight) {
      _lastWidth = buffer.viewWidth;
      _lastHeight = buffer.viewHeight;
      _reset();
      return;
    }

    final now = clock();

    var latestConfirmed = -1;
    for (final entry in _rows.entries) {
      final line = entry.key;
      if (_screenRow(buffer, line) == null) continue;
      final cells = entry.value;
      for (var col = 0; col < cells.length; col++) {
        final p = cells[col];
        if (p != null &&
            p.earnsCredit &&
            col < line.length &&
            _sameContent(line.getCodePoint(col), p.codePoint)) {
          latestConfirmed = max(latestConfirmed, p.time);
          if (p.epoch > _confirmedEpoch) _confirmedEpoch = p.epoch;
        }
      }
    }

    final acks = _acked >= 0;
    bool acknowledged(int seq) =>
        _acked >= seq && now - _ackedAt >= _kEchoGraceMs;
    final caughtUp =
        (acks ? acknowledged(_sent) : now - _lastInputAt >= _settleMs) ||
        now - _lastInputAt >= _kGiveUpMs;

    final cursorLine = buffer.currentLine;

    bool processed(_CellPrediction p, BufferLine line) =>
        caughtUp ||
        line != cursorLine ||
        acknowledged(p.seq) ||
        p.time <= latestConfirmed ||
        (!acks && fromOutput && now - p.time > _settleMs) ||
        now - p.time >= _kGiveUpMs;

    int? killFrom;

    for (final entry in _rows.entries) {
      final line = entry.key;
      final cells = entry.value;
      if (_screenRow(buffer, line) == null) {
        cells.fillRange(0, cells.length, null);
        continue;
      }

      for (var col = 0; col < cells.length; col++) {
        final p = cells[col];
        if (p == null) continue;

        final current = col < line.length ? line.getCodePoint(col) : 0;
        final matches = _sameContent(current, p.codePoint);
        final contradicted =
            !matches &&
            !_isBlank(current) &&
            !p.originals.any((o) => _sameContent(o, current));

        if (!processed(p, line) && !matches && !contradicted) {
          final age = now - p.time;
          if (age >= _kGlitchDimMs) {
            _glitchTrigger = _kGlitchRepairCount * 2;
          } else if (age >= _kGlitchMs &&
              _glitchTrigger < _kGlitchRepairCount) {
            _glitchTrigger = _kGlitchRepairCount;
          }
          continue;
        }

        if (matches) {
          if (p.earnsCredit &&
              now - p.time < _kGlitchMs &&
              _glitchTrigger > 0 &&
              now - _kGlitchRepairIntervalMs >= _lastQuickConfirmation) {
            _glitchTrigger--;
            _lastQuickConfirmation = now;
          }
          cells[col] = null;
          continue;
        }

        if (_isTentative(p.epoch)) {
          killFrom = _earliest(killFrom, p.epoch);
          cells[col] = null;
          continue;
        }

        _reset();
        _updateTriggers();
        return;
      }
    }

    _rows.removeWhere((_, cells) => cells.every((p) => p == null));

    if (latestConfirmed >= 0) {
      _sampleEcho((now - latestConfirmed).toDouble());
    }

    if (killFrom != null) _killEpoch(killFrom);

    final cursor = _cursor;
    if (cursor != null && _screenRow(buffer, cursor.line) != buffer.cursorY) {
      _reset();
      _updateTriggers();
      return;
    }

    if (caughtUp) {
      final cursor = _cursor;
      if (cursor != null) {
        final right =
            _screenRow(buffer, cursor.line) == buffer.cursorY &&
            cursor.col == buffer.cursorX;
        if (!right && !_isTentative(cursor.epoch)) _rows.clear();
      }
      _cursor = null;
      if (_lost) {
        _lost = false;
        _becomeTentative();
      }
    }

    _updateTriggers();
  }

  void _sampleEcho(double sample) {
    final srtt = _srtt;
    _srtt = srtt == null ? sample : srtt * 7 / 8 + sample / 8;
  }

  void _updateTriggers() {
    final srtt = _srtt;
    if (srtt == null) return;

    if (srtt > _kShowAboveMs) {
      _srttTrigger = true;
    } else if (_srttTrigger && srtt <= _kHideAtOrBelowMs && !_hasPredictions) {
      _srttTrigger = false;
    }

    if (srtt > _kDimAboveMs) {
      _dimmed = true;
    } else if (srtt <= _kUndimAtOrBelowMs) {
      _dimmed = false;
    }

    if (_glitchTrigger > _kGlitchRepairCount) _dimmed = true;
  }

  void _predict(Buffer buffer, List<int> runes) {
    _lastWidth = buffer.viewWidth;
    _lastHeight = buffer.viewHeight;

    var i = 0;
    while (i < runes.length) {
      final ch = runes[i];

      if (ch == 0x1b) {
        i = _escape(buffer, runes, i);
        continue;
      }

      i++;

      if (ch == 0x7f) {
        _backspace(buffer);
      } else if (_isNarrow(ch)) {
        _print(buffer, ch);
      } else {
        _loseTrack();
      }
    }
  }

  /// Handles the escape sequence starting at [start] and returns the index
  /// after it. Only the plain left arrow is predicted - `ESC [ D`, or `ESC O D`
  /// in application cursor mode. Right arrow is not: at the end of the line it
  /// does nothing in bash and accepts a suggestion in zsh.
  int _escape(Buffer buffer, List<int> runes, int start) {
    var i = start + 1;
    if (i >= runes.length) {
      _loseTrack();
      return i;
    }

    final introducer = runes[i++];
    if (introducer != 0x5b && introducer != 0x4f) {
      _loseTrack();
      return i;
    }

    final paramsStart = i;
    while (i < runes.length && (runes[i] < 0x40 || runes[i] > 0x7e)) {
      i++;
    }
    if (i >= runes.length) {
      _loseTrack();
      return i;
    }

    final hasParams = i > paramsStart;
    final finalByte = runes[i++];

    if (!hasParams && finalByte == 0x44) {
      _left(buffer);
    } else {
      _loseTrack();
    }
    return i;
  }

  /// The cursor's predicted position, or null while it is unknown.
  _CursorPrediction? _trackedCursor(Buffer buffer) {
    if (_lost) return null;
    var cursor = _cursor;
    if (cursor == null) {
      cursor = _CursorPrediction(
        line: buffer.currentLine,
        col: buffer.cursorX,
        epoch: _predictionEpoch,
      );
      _cursor = cursor;
    } else if (cursor.epoch != _predictionEpoch) {
      cursor.epoch = _predictionEpoch;
    }
    if (_screenRow(buffer, cursor.line) == null) {
      _loseTrack();
      return null;
    }
    return cursor;
  }

  /// Whether the cell left of [cursor] is one typed on this line - where
  /// backspace and left arrow can safely go.
  bool _typedLeftOf(_CursorPrediction cursor) =>
      _inputLine == cursor.line && cursor.col > _inputStart;

  void _left(Buffer buffer) {
    final cursor = _trackedCursor(buffer);
    if (cursor == null) return;
    if (!_typedLeftOf(cursor)) {
      _loseTrack();
      return;
    }
    cursor.col--;
  }

  /// Predicts printing [ch] at the cursor.
  ///
  /// The last column is where a terminal defers its wrap; what follows is up
  /// to the program, so printing there loses track instead. Typing the
  /// character already under the cursor is typing along an autosuggestion:
  /// the shell takes it over in place. Anything else with text after the
  /// cursor - more of the line, or a suggestion this key breaks - rearranges
  /// in a way only the server knows, so the key is held back until its echo
  /// instead of being drawn wrong and taken back.
  void _print(Buffer buffer, int ch) {
    var cursor = _trackedCursor(buffer);
    if (cursor == null) return;
    final line = cursor.line;
    final col = cursor.col;

    if (col + 1 >= buffer.viewWidth) {
      _loseTrack();
      return;
    }

    if (_inputLine != line) {
      _inputLine = line;
      _inputStart = col;
    }

    final old = _contentsOf(buffer, line);
    final here = old[col];
    final left = col > 0 ? old[col - 1] : here;
    final typed = _Content(ch, left.foreground, left.background, left.flags);

    if (here.codePoint != ch && _textFollows(old, col)) {
      _becomeTentative();
      cursor = _trackedCursor(buffer)!;
    }

    _renew(line, col, clock()).content = typed;
    cursor.col++;
  }

  /// Moves the cursor back and leaves the cell alone. What takes the deleted
  /// character's place is not always a blank - an autosuggestion reappears
  /// there - so the cell keeps what it shows until the echo says.
  void _backspace(Buffer buffer) {
    final cursor = _trackedCursor(buffer);
    if (cursor == null) return;
    if (!_typedLeftOf(cursor)) {
      _loseTrack();
      return;
    }
    cursor.col--;
  }

  /// Whether anything but blanks sits at or after [from], short of the first
  /// gap of two blanks - which is where the text ends, and anything further
  /// along, a right-hand prompt, is not part of it.
  bool _textFollows(List<_Content> contents, int from) {
    for (var i = from; i < contents.length; i++) {
      if (!contents[i].isBlank) return true;
      if (i + 1 < contents.length && contents[i + 1].isBlank) return false;
    }
    return false;
  }

  List<_Content> _contentsOf(Buffer buffer, BufferLine line) => [
    for (var i = 0; i < buffer.viewWidth; i++) _contentAt(line, i),
  ];

  _Content _contentAt(BufferLine line, int col) {
    final predicted = _rows[line]?[col];
    if (predicted != null) return predicted.content;
    if (col >= line.length) return const _Content.blank();
    return _Content(
      line.getCodePoint(col),
      line.getForeground(col),
      line.getBackground(col),
      line.getAttributes(col),
    );
  }

  _CellPrediction _renew(BufferLine line, int col, int now) {
    final cells = _rows.putIfAbsent(
      line,
      () => List<_CellPrediction?>.filled(_lastWidth, null),
    );
    final previous = cells[col];
    final p = _CellPrediction(epoch: _predictionEpoch, time: now, seq: _sent);
    if (previous != null) {
      p.originals
        ..addAll(previous.originals)
        ..add(previous.codePoint);
    }
    if (col < line.length) p.originals.add(line.getCodePoint(col));
    cells[col] = p;
    return p;
  }
}

/// Whether [ch] is certain to take exactly one cell. Deliberately short of a
/// full width table: anything else is simply not predicted.
bool _isNarrow(int ch) =>
    (ch >= 0x20 && ch < 0x7f) ||
    (ch >= 0xa0 && ch < 0x300) ||
    (ch >= 0x370 && ch < 0x483) ||
    (ch >= 0x48a && ch < 0x530);

int _earliest(int? a, int b) => a == null || b < a ? b : a;

bool _isBlank(int codePoint) => codePoint == 0 || codePoint == 0x20;

bool _sameContent(int a, int b) => a == b || (_isBlank(a) && _isBlank(b));

class _Content {
  const _Content(this.codePoint, this.foreground, this.background, this.flags);

  const _Content.blank()
    : codePoint = 0x20,
      foreground = 0,
      background = 0,
      flags = 0;

  final int codePoint;
  final int foreground;
  final int background;
  final int flags;

  bool get isBlank => _isBlank(codePoint);
}

class _CellPrediction {
  _CellPrediction({required this.epoch, required this.time, required this.seq});

  final int epoch;

  final int time;

  /// The input that made it, for [PredictiveEcho.acknowledge].
  final int seq;

  var content = const _Content.blank();

  /// What the cell held before, including earlier predictions for it. A
  /// prediction that matches one of these proves nothing when it matches.
  final originals = <int>[];

  int get codePoint => content.codePoint;
  int get foreground => content.foreground;
  int get background => content.background;
  int get flags => content.flags;

  bool get earnsCredit =>
      !_isBlank(codePoint) && !originals.any((o) => _sameContent(o, codePoint));
}

class _CursorPrediction {
  _CursorPrediction({
    required this.line,
    required this.col,
    required this.epoch,
  });

  final BufferLine line;

  int col;

  int epoch;
}

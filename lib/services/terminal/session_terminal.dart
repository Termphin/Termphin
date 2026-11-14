import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:terminal_view/terminal_view.dart';

/// Lines of scrollback a session keeps.
const kTerminalScrollbackLines = 10000;

/// A session's terminal - the screen, its scrollback and the parser feeding
/// them - alive for as long as the session is.
///
/// It belongs to the session, not to the widget that draws it. The widget
/// used to own the terminal and was rebuilt from the session's raw output on
/// every return to the session, which only kept the last half megabyte: a
/// program that redraws constantly (a spinner, a progress bar) filled that
/// with redraws and everything said before it was gone. Parsing as the bytes
/// arrive, seen or not, means what the pane shows on return is what it would
/// have shown had it never left.
///
/// It starts at the size the pty was opened with, so what the program draws
/// before any pane has laid out is parsed at the size it was drawn for; the
/// pane's first layout then resizes both.
///
/// A pane [bind]s to it while mounted and [release]s it on the way out. In
/// between nobody is looking, but the program on the far end still asks its
/// questions - cursor position, device attributes - so the answers go to
/// [onReply] rather than nowhere.
class SessionTerminal {
  SessionTerminal({
    int columns = 80,
    int rows = 24,
    Uint8List? replay,
    this.onReply,
  }) : terminal = _SessionTerminalCore(
         maxLines: kTerminalScrollbackLines,
         platform: _terminalPlatform(defaultTargetPlatform),
       ) {
    terminal
      ..resize(columns, rows)
      ..onOutput = _reply;
    _utf8Sink = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_StringChunkSink(_decoded));
    if (replay != null && replay.isNotEmpty) {
      _replayBytesLeft = replay.length;
      _enqueue(replay);
    }
  }

  final Terminal terminal;

  /// Takes what the terminal answers the program with while no pane is bound.
  void Function(String data)? onReply;

  /// Output arrives from SSH in whatever sized pieces the network hands
  /// over, often many per frame. Feeding each one straight to the terminal
  /// parses and repaints once per piece; queueing them here instead means
  /// one parse and one repaint for everything that showed up since the
  /// last drain.
  final _pendingBytes = Queue<Uint8List>();
  int _pendingLength = 0;
  bool _retired = false;
  final _decoded = StringBuffer();
  late final ByteConversionSink _utf8Sink;
  Object? _owner;

  /// Largest slice handed to the parser between looks at the clock.
  static const _drainSlice = 4096;

  /// Output waiting this long is no longer something to get to later: left
  /// alone, a session nobody is looking at would queue a large `cat` whole.
  static const _backlogLimit = 1024 * 1024;

  /// Whether this terminal is parsed ahead of the others: somebody is
  /// looking at it, or it has fallen too far behind.
  bool get _urgent => _owner != null || _pendingLength > _backlogLimit;

  /// Bytes of the replay this terminal was started from still waiting to be
  /// parsed.
  int _replayBytesLeft = 0;

  /// Whether what is being parsed is a replay of something that already
  /// happened. Anything with a side effect outside the screen - a clipboard
  /// write, an answer to a query - happened then and must not happen again.
  bool get replaying => _replayBytesLeft > 0;

  /// Queues [bytes] of output for the parser.
  void add(Uint8List bytes) => _enqueue(bytes);

  /// Hands the terminal's callbacks to [owner], the pane now drawing it.
  ///
  /// A later [bind] takes them over: after a reconnect the new pane is
  /// mounted while the one it replaces is still on screen, and the old one's
  /// [release] must not take them back off the new one.
  void bind(
    Object owner, {
    required void Function(String data) onOutput,
    required void Function(int columns, int rows) onResize,
    void Function()? onBell,
    void Function(String code, List<String> args)? onPrivateOsc,
  }) {
    _owner = owner;
    if (_pendingBytes.isNotEmpty) {
      TerminalParseScheduler.instance._request(this);
    }
    terminal
      ..onOutput = onOutput
      ..onResize = ((columns, rows, _, _) => onResize(columns, rows))
      ..onBell = onBell
      ..onPrivateOSC = onPrivateOsc;
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    terminal
      ..onOutput = _reply
      ..onResize = null
      ..onBell = null
      ..onPrivateOSC = null;
  }

  /// Parses everything queued, now, however long it takes.
  void flush() {
    while (_pendingBytes.isNotEmpty) {
      _drain();
    }
  }

  /// Stops parsing for good. The terminal itself is left as it stands: a
  /// pane may still be drawing it while its replacement gets ready.
  void retire() {
    _retired = true;
    _pendingBytes.clear();
    _pendingLength = 0;
    TerminalParseScheduler.instance._forget(this);
    terminal.dispose();
  }

  void _reply(String data) {
    if (replaying) return;
    onReply?.call(data);
  }

  void _enqueue(Uint8List data) {
    if (data.isEmpty || _retired) return;
    _pendingBytes.addLast(data);
    _pendingLength += data.length;
    TerminalParseScheduler.instance._request(this);
  }

  /// Parses until the queue is empty or [clock] reaches [until]; with no
  /// clock, until the queue is empty or the replay ends.
  ///
  /// The pass ends exactly where the replay does - live output queued behind
  /// it would otherwise be parsed in the same `terminal.write` and take the
  /// replay's suppression with it. The write itself still runs while
  /// [_replayBytesLeft] covers these bytes, so the handlers it reaches can
  /// tell replayed sequences from live ones - and is counted off afterwards
  /// even when a handler throws, or everything after it would pass for a
  /// replay.
  void _drain({Stopwatch? clock, Duration until = Duration.zero}) {
    if (_retired || _pendingBytes.isEmpty) return;

    final replaying = _replayBytesLeft > 0;
    var fed = 0;

    while (_pendingBytes.isNotEmpty) {
      final chunk = _pendingBytes.first;
      var take = chunk.length <= _drainSlice ? chunk.length : _drainSlice;
      if (replaying && fed + take > _replayBytesLeft) {
        take = _replayBytesLeft - fed;
      }

      _pendingBytes.removeFirst();
      if (take < chunk.length) {
        _pendingBytes.addFirst(Uint8List.sublistView(chunk, take));
      }
      _utf8Sink.add(Uint8List.sublistView(chunk, 0, take));
      fed += take;

      if (replaying && fed >= _replayBytesLeft) break;
      if (clock != null && clock.elapsed >= until) break;
    }

    _pendingLength -= fed;
    if (_decoded.isEmpty) {
      if (replaying) _replayBytesLeft -= fed;
      return;
    }
    final text = _decoded.toString();
    _decoded.clear();
    try {
      terminal.write(text);
    } finally {
      if (replaying) _replayBytesLeft -= fed;
    }
  }
}

/// Shares out the time the UI thread spends parsing among every session's
/// terminal.
///
/// Each terminal used to pace itself, which was right while only the one on
/// screen parsed at all. With every session parsing as its output arrives,
/// three busy sessions in the background each took their own slice between
/// two frames and the one on screen dropped them. So there is one slice a
/// turn, sized to the screen's refresh rate rather than fixed, and it goes to
/// the terminals somebody is looking at first. The rest are parsed in what is
/// left of it, or - when nobody on screen has anything waiting - in half a
/// slice once a frame, which keeps up with anything a shell prints and
/// leaves the frame alone. A terminal that falls a megabyte behind stops
/// being polite.
class TerminalParseScheduler {
  TerminalParseScheduler._();

  static final instance = TerminalParseScheduler._();

  /// Share of a frame one turn may spend parsing. A frame also has to lay
  /// out and paint what was parsed.
  static const _frameShare = 0.3;
  static const _shortestSlice = Duration(microseconds: 1500);
  static const _longestSlice = Duration(milliseconds: 6);

  final _waiting = <SessionTerminal>{};

  /// A turn is on its way: by microtask or at the next event, [_soon], or
  /// after a frame's pause, [_later]. [_scheduledIn] is the zone it was
  /// scheduled in - a zone that is gone (a finished test's fake clock) never
  /// runs what it was given, and the next request must not wait for it.
  bool _soon = false;
  Timer? _later;
  Zone? _scheduledIn;

  /// The refresh rate turns are sized for, when the platform does not say.
  @visibleForTesting
  double? refreshRateOverride;

  Duration get _framePeriod {
    var rate = refreshRateOverride ?? 0;
    if (rate <= 0) {
      try {
        rate =
            PlatformDispatcher.instance.implicitView?.display.refreshRate ?? 0;
      } on Object {
        rate = 0;
      }
    }
    if (rate <= 0) rate = 60;
    return Duration(
      microseconds: (Duration.microsecondsPerSecond / rate).round(),
    );
  }

  /// What one turn may spend parsing at the current refresh rate.
  @visibleForTesting
  Duration get slice {
    final micros = (_framePeriod.inMicroseconds * _frameShare).round();
    return Duration(
      microseconds: micros.clamp(
        _shortestSlice.inMicroseconds,
        _longestSlice.inMicroseconds,
      ),
    );
  }

  void _request(SessionTerminal terminal) {
    _waiting.add(terminal);
    final stale = !identical(_scheduledIn, Zone.current);
    if (terminal._urgent) {
      if (_soon && !stale) return;
      _later?.cancel();
      _later = null;
      _soon = true;
      _scheduledIn = Zone.current;
      scheduleMicrotask(_turn);
      return;
    }
    if ((_soon || _later != null) && !stale) return;
    _later?.cancel();
    _soon = false;
    _scheduledIn = Zone.current;
    _later = Timer(_framePeriod, _turn);
  }

  void _forget(SessionTerminal terminal) => _waiting.remove(terminal);

  /// The first turn after idle goes out on a microtask so an echoed
  /// keystroke still lands in the same frame. Continuations go through the
  /// event loop instead, giving the frame that was just scheduled a chance
  /// to actually render before more parsing starts.
  void _turn() {
    _soon = false;
    _later?.cancel();
    _later = null;

    final urgent = <SessionTerminal>[];
    final patient = <SessionTerminal>[];
    for (final terminal in [..._waiting]) {
      if (terminal._retired || terminal._pendingBytes.isEmpty) {
        _waiting.remove(terminal);
      } else {
        (terminal._urgent ? urgent : patient).add(terminal);
      }
    }
    if (urgent.isEmpty && patient.isEmpty) return;

    final clock = Stopwatch()..start();
    final slice = this.slice;
    try {
      _parse(urgent, clock, slice);
      _parse(patient, clock, urgent.isEmpty ? slice ~/ 2 : slice);
    } finally {
      _scheduleNext(urgent, patient);
    }
  }

  /// Puts back whoever still has output waiting and books the next turn.
  /// Run even when a terminal's handler threw during the turn: the others
  /// have nothing to do with it and would otherwise wait for output of
  /// their own to be looked at again.
  void _scheduleNext(
    List<SessionTerminal> urgent,
    List<SessionTerminal> patient,
  ) {
    var urgentLeft = false;
    var anyLeft = false;
    final served = [...urgent, ...patient.skip(1), ...patient.take(1)];
    for (final terminal in served) {
      _waiting.remove(terminal);
      if (terminal._pendingBytes.isEmpty) continue;
      _waiting.add(terminal);
      anyLeft = true;
      urgentLeft = urgentLeft || terminal._urgent;
    }
    if (!anyLeft) return;
    _scheduledIn = Zone.current;
    if (urgentLeft) {
      _soon = true;
      Timer.run(_turn);
    } else {
      _later = Timer(_framePeriod, _turn);
    }
  }

  /// Gives each of [terminals] an equal part of what is left until [limit].
  /// The first parses at least a little whatever the clock says, and the
  /// patient ones take turns at being first, so none of them is starved by
  /// a terminal on screen that never runs dry.
  void _parse(
    List<SessionTerminal> terminals,
    Stopwatch clock,
    Duration limit,
  ) {
    for (var index = 0; index < terminals.length; index++) {
      final elapsed = clock.elapsed;
      final left = limit - elapsed;
      if (left <= Duration.zero && index > 0) return;
      final share = left <= Duration.zero
          ? Duration.zero
          : left ~/ (terminals.length - index);
      terminals[index]._drain(clock: clock, until: elapsed + share);
    }
  }
}

/// A terminal that leaves itself alone when asked to resize to the size it
/// already has.
///
/// `Terminal.resize` resets the scroll margins and, on the alternate screen,
/// drops the scrollback, whatever the new size is. That was harmless while
/// every pane started on a blank terminal. A pane mounting on one that a
/// program is in the middle of drawing lays out, asks for the size the
/// terminal already has, and would take the program's scroll region away
/// with no window-change to make it set the region again.
class _SessionTerminalCore extends Terminal {
  _SessionTerminalCore({super.maxLines, super.platform});

  @override
  void resize(
    int newWidth,
    int newHeight, [
    int? pixelWidth,
    int? pixelHeight,
  ]) {
    final columns = newWidth < 1 ? 1 : newWidth;
    final rows = newHeight < 1 ? 1 : newHeight;
    if (columns == viewWidth && rows == viewHeight) {
      onResize?.call(columns, rows, pixelWidth ?? 0, pixelHeight ?? 0);
      return;
    }
    super.resize(newWidth, newHeight, pixelWidth, pixelHeight);
  }
}

TerminalTargetPlatform _terminalPlatform(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android => TerminalTargetPlatform.android,
      TargetPlatform.iOS => TerminalTargetPlatform.ios,
      TargetPlatform.linux => TerminalTargetPlatform.linux,
      TargetPlatform.macOS => TerminalTargetPlatform.macos,
      TargetPlatform.windows => TerminalTargetPlatform.windows,
      TargetPlatform.fuchsia => TerminalTargetPlatform.fuchsia,
    };

/// Collects the decoder's output so a whole drain can be handed to the
/// terminal as one write.
class _StringChunkSink implements Sink<String> {
  _StringChunkSink(this._buffer);

  final StringBuffer _buffer;

  @override
  void add(String data) => _buffer.write(data);

  @override
  void close() {}
}

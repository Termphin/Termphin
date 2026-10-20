import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:terminal_view/terminal_view.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../services/completion/command_line_reader.dart';
import '../../services/terminal/predictive_echo.dart';
import '../../services/terminal/terminal_search.dart';
import '../../services/terminal/terminal_text.dart';
import '../../theme/theme.dart' as app_theme;
import '../ui/app_notifications.dart';
import 'terminal_search_bar.dart';

const kTerminalScrollbackLines = 10000;

/// The fewest rows the PTY is ever told it has.
///
/// `terminal_view` sizes the viewport as height minus padding, so a pane short
/// enough for the padding to outrun it produces a *negative* viewport. That
/// reaches the server as a window-change of 4294967295 rows, and the remote
/// shell does not survive the next screenful of output.
const _kMinTerminalRows = 3;

/// Room left under the last line: breathing space that scales with the line
/// height, capped so [_kMinTerminalRows] always fit.
///
/// The keyboard is not part of this sum. The pane is laid out inside a
/// `Scaffold` that resizes for the keyboard, so by the time this is asked the
/// height it is given already excludes it.
double terminalBottomPadding({
  required double availableHeight,
  required double lineHeight,
  required double cellHeight,
}) {
  final wanted = 4 * lineHeight;
  if (!availableHeight.isFinite || availableHeight <= 0) return wanted;
  final floor = cellHeight > 0 ? cellHeight * _kMinTerminalRows : 0.0;
  final ceiling = math.max(0.0, availableHeight - floor);
  return math.min(wanted, ceiling);
}

/// True while a finger drags a selection: from the moment it lands on a
/// selection handle, or a long press starts selecting, until it lifts.
///
/// The session swipe in `TerminalScreen` reads raw pointers through a
/// [Listener], which never enters the gesture arena, so it cannot lose to the
/// selection's recogniser the way a competing gesture would - both run. That
/// is how stretching a selection sideways ends up paging between tabs. The
/// selection claims the pointer here instead, and the swipe checks the flag
/// on every move.
final ValueNotifier<bool> terminalSelectionDragActive = ValueNotifier(false);

class TerminalPaneController {
  _TerminalPaneState? _state;

  void _attach(_TerminalPaneState state) => _state = state;

  void _detach(_TerminalPaneState state) {
    if (identical(_state, state)) _state = null;
  }

  void focusTerminal() => _state?.focusTerminal();

  void blurTerminal() => _state?.blurTerminal();

  Future<void> pause() async => blurTerminal();

  void setFontSize(double size) => _state?.setFontSize(size);

  void setFontFamily(String fontFamily) => _state?.setFontFamily(fontFamily);

  void setCursorBlink(bool blink) => _state?.setCursorBlink(blink);

  void setCursorStyle(String style) => _state?.setCursorStyle(style);

  void setPredictiveEcho(bool enabled) => _state?.setPredictiveEcho(enabled);

  void scrollToBottom() => _state?.scrollToBottom();

  /// Opens the search bar over the terminal, or focuses it if it is open.
  void openSearch() => _state?.openSearch();

  /// Whether a full-screen program (vim, less, htop) has the screen.
  bool get isUsingAltBuffer => _state?._terminal.isUsingAltBuffer ?? false;

  /// Whether the shell asked for pastes to be bracketed.
  bool get bracketedPasteMode => _state?._terminal.bracketedPasteMode ?? false;

  void setColors(app_theme.TerminalColorScheme colors) =>
      _state?.setColors(colors);

  Future<String?> getSelectedText() async => _state?.selectedText;

  /// See [terminalBufferText]; null before the pane is attached.
  String? bufferText() =>
      _state == null ? null : terminalBufferText(_state!._terminal.buffer);

  void clearSelection() => _state?.clearSelection();

  void doCopy() => _state?.copySelection();

  void setLineHeight(double lineHeight) => _state?.setLineHeight(lineHeight);

  void setSidePadding(double padding) => _state?.setSidePadding(padding);

  /// The settled keyboard height - resizes the PTY, once per open or close.
  void requestFit() => _state?.requestFit();

  void enterFollowMode() => _state?.scrollToBottom();

  void refreshTerminal() => _state?.refreshTerminal();

  /// The cursor's current on-screen position, in the coordinate space of the
  /// Stack this pane sits in - null before the terminal has laid out.
  /// Recomputed on each call rather than tracked continuously: callers ask
  /// for it once, at the moment they want to anchor something to it (see
  /// [CursorMenu]).
  Offset? cursorOffsetInStack() => _state?._cursorOffsetInStack();

  /// What is typed at the shell prompt; see [CommandLineReader.read].
  String? readCommandLine() => _state?._commandLine.read();

  /// See [CommandLineReader.textFollowsCursor].
  bool textFollowsCursor() => _state?._commandLine.textFollowsCursor() ?? false;

  /// The cursor's cell, in the coordinate space of the Stack this pane sits
  /// in - null before the terminal has laid out.
  Rect? cursorRectInStack() => _state?._cursorRectInStack();

  /// Called with each command line as it is submitted.
  void Function(String command)? onCommandSubmitted;

  final _screenListeners = <VoidCallback>{};

  /// Called on every change to the screen - every write, so often.
  void addScreenListener(VoidCallback listener) =>
      _screenListeners.add(listener);

  void removeScreenListener(VoidCallback listener) =>
      _screenListeners.remove(listener);

  void _screenChanged() {
    for (final listener in [..._screenListeners]) {
      listener();
    }
  }
}

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.outputStream,
    this.inputStream,
    this.inputReceipts,
    required this.onInput,
    required this.onResize,
    this.controller,
    this.onFontSizeChanged,
    this.onSelectionStateChanged,
    this.onScrollModeChanged,
    this.onLinkDetected,
    this.initialHistory,
    this.onReady,
  });

  final Stream<Uint8List> outputStream;

  /// What was actually sent to the shell, after any modifier the session
  /// applied to [onInput] - the bytes predictive echo predicts from.
  final Stream<SessionInput>? inputStream;

  /// The highest input number the server has confirmed receiving.
  final Stream<int>? inputReceipts;
  final void Function(List<int> bytes) onInput;
  final void Function(int cols, int rows) onResize;
  final TerminalPaneController? controller;
  final void Function(double fontSize)? onFontSizeChanged;
  final void Function(bool active, double topY, double bottomY)?
  onSelectionStateChanged;
  final void Function(bool isManual)? onScrollModeChanged;
  final void Function(String url, double tapY)? onLinkDetected;
  final Uint8List? initialHistory;
  final VoidCallback? onReady;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _terminalController = TerminalController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  /// Output arrives from SSH in whatever sized pieces the network hands
  /// over, often many per frame. Feeding each one straight to the terminal
  /// parses and repaints once per piece; queueing them here instead means
  /// one parse and one repaint for everything that showed up since the
  /// last drain.
  final _pendingBytes = Queue<Uint8List>();
  bool _drainScheduled = false;

  /// Until the first layout, the terminal is still 80x24; output parsed at
  /// that size addresses rows the real viewport has but this buffer
  /// doesn't.
  bool _terminalSized = false;
  final _decoded = StringBuffer();
  late final ByteConversionSink _utf8Sink;

  /// How long a single drain may spend parsing before it yields. A burst of
  /// output - `cat` on something large, a build log - would otherwise hold the
  /// UI thread for as long as it takes to parse the whole thing, and the
  /// terminal would stop responding to touch until it finished.
  static const _drainBudget = Duration(milliseconds: 6);

  /// Largest slice handed to the parser between budget checks.
  static const _drainSlice = 4096;

  /// Bytes of [TerminalPane.initialHistory] still waiting to be parsed.
  ///
  /// The replay is the raw scrollback, escape sequences and all, so anything
  /// with a side effect outside the screen happens again every time the pane
  /// remounts. For OSC 52 that means a copy the remote side asked for once
  /// silently taking the clipboard back over on every return to the session,
  /// until the sequence finally scrolls out of the history ring.
  int _replayBytesLeft = 0;

  late final Terminal _terminal;
  late final PredictiveEcho _predictiveEcho;
  late final CommandLineReader _commandLine;
  StreamSubscription<Uint8List>? _outputSubscription;
  StreamSubscription<SessionInput>? _inputSubscription;
  StreamSubscription<int>? _receiptSubscription;

  _SelectionGeometry? _selection;
  CellOffset? _dragAnchorCell;
  Offset? _dragLocal;
  Timer? _autoScrollTimer;

  bool _searchOpen = false;
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchCaseSensitive = false;

  /// Anchored, so they follow their text as output arrives and the view
  /// scrolls.
  final _searchMatches = <(CellAnchor, CellAnchor)>[];
  final _searchHighlights = <TerminalHighlight>[];
  TerminalHighlight? _currentHighlight;
  int _searchIndex = 0;
  Timer? _searchRefresh;

  double _fontSize = 12;
  String _fontFamily = 'HackNerdFontMono';
  double _lineHeight = 1;
  double _sidePadding = 6;
  bool _cursorBlink = true;
  String _cursorStyle = 'block';
  app_theme.TerminalColorScheme _colors =
      app_theme.AppTheme.terminalSchemeDefault;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: kTerminalScrollbackLines,
      platform: _terminalPlatform(defaultTargetPlatform),
      onOutput: (data) => widget.onInput(utf8.encode(data)),
      onResize: (width, height, _, _) {
        if (!_terminalSized) {
          _terminalSized = true;
          _scheduleDrain(immediate: true);
        }
        widget.onResize(width, height);
      },
      onBell: HapticFeedback.mediumImpact,
      onPrivateOSC: _handlePrivateOSC,
    );
    _predictiveEcho = PredictiveEcho(_terminal)..attach();
    _commandLine = CommandLineReader(_terminal)
      ..onSubmit = (command) =>
          widget.controller?.onCommandSubmitted?.call(command);
    _terminal.addListener(_onTerminalChanged);
    _terminalController.addListener(_onSelectionChanged);
    _scrollController.addListener(_onScrollChanged);
    widget.controller?._attach(this);

    _utf8Sink = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_StringChunkSink(_decoded));
    final initialHistory = widget.initialHistory;
    if (initialHistory != null && initialHistory.isNotEmpty) {
      _replayBytesLeft = initialHistory.length;
      _enqueue(initialHistory);
    }
    _listenToOutput();
    _listenToInput();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady?.call();
    });
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outputStream != widget.outputStream) {
      _listenToOutput();
    }
    if (oldWidget.inputStream != widget.inputStream ||
        oldWidget.inputReceipts != widget.inputReceipts) {
      _listenToInput();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    _terminal.onOutput = (data) => widget.onInput(utf8.encode(data));
    _terminal.onResize = (width, height, _, _) =>
        widget.onResize(width, height);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _autoScrollTimer?.cancel();
    _searchRefresh?.cancel();
    _clearSearchMatches();
    _searchField.dispose();
    _searchFocus.dispose();
    _outputSubscription?.cancel();
    _inputSubscription?.cancel();
    _receiptSubscription?.cancel();
    _predictiveEcho.dispose();
    _terminal.removeListener(_onTerminalChanged);
    _pendingBytes.clear();
    _terminalController
      ..removeListener(_onSelectionChanged)
      ..dispose();
    _scrollController
      ..removeListener(_onScrollChanged)
      ..dispose();
    _focusNode.dispose();
    _terminal.dispose();
    super.dispose();
  }

  void _listenToOutput() {
    unawaited(_outputSubscription?.cancel());
    _outputSubscription = widget.outputStream.listen(_enqueue);
  }

  void _listenToInput() {
    unawaited(_inputSubscription?.cancel());
    unawaited(_receiptSubscription?.cancel());
    _inputSubscription = widget.inputStream?.listen((input) {
      final text = utf8.decode(input.bytes, allowMalformed: true);
      _commandLine.userInput(text);
      _predictiveEcho.userInput(text, input.seq);
    });
    _receiptSubscription = widget.inputReceipts?.listen(
      _predictiveEcho.acknowledge,
    );
  }

  /// Output keeps coming while the search bar is open; recount once it
  /// settles.
  void _onTerminalChanged() {
    widget.controller?._screenChanged();
    if (!_searchOpen || _searchField.text.isEmpty) return;
    _searchRefresh?.cancel();
    _searchRefresh = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _searchOpen) _runSearch(reveal: false);
    });
  }

  void openSearch() {
    if (!_searchOpen) {
      setState(() => _searchOpen = true);
      if (_searchField.text.isNotEmpty) _runSearch(reveal: true);
    }
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchRefresh?.cancel();
    _clearSearchMatches();
    setState(() => _searchOpen = false);
  }

  void _clearSearchMatches() {
    _currentHighlight?.dispose();
    _currentHighlight = null;
    for (final highlight in _searchHighlights) {
      highlight.dispose();
    }
    _searchHighlights.clear();
    for (final (begin, end) in _searchMatches) {
      begin.dispose();
      end.dispose();
    }
    _searchMatches.clear();
  }

  /// Finds the query again over the whole buffer. A refresh keeps the match
  /// in focus where it was; a new query starts from the newest one.
  void _runSearch({required bool reveal}) {
    CellOffset? kept;
    if (!reveal && _searchIndex < _searchMatches.length) {
      final (begin, _) = _searchMatches[_searchIndex];
      if (begin.attached) kept = begin.offset;
    }
    _clearSearchMatches();
    final buffer = _terminal.buffer;
    final matches = findInBuffer(
      buffer,
      _searchField.text,
      caseSensitive: _searchCaseSensitive,
    );
    final color = _colors.yellow.withValues(alpha: 0.35);
    for (final match in matches) {
      final begin = buffer.lines[match.begin.y].createAnchor(match.begin.x);
      final end = buffer.lines[match.end.y].createAnchor(match.end.x);
      _searchMatches.add((begin, end));
      _searchHighlights.add(
        _terminalController.highlight(p1: begin, p2: end, color: color),
      );
    }
    final keptIndex = kept == null
        ? -1
        : matches.indexWhere((match) => match.begin == kept);
    _focusSearchMatch(
      keptIndex >= 0 ? keptIndex : matches.length - 1,
      reveal: reveal,
    );
  }

  void _stepSearch(int delta) {
    if (_searchMatches.isEmpty) return;
    final count = _searchMatches.length;
    _focusSearchMatch((_searchIndex + delta) % count, reveal: true);
  }

  void _focusSearchMatch(int index, {required bool reveal}) {
    _currentHighlight?.dispose();
    _currentHighlight = null;
    setState(() => _searchIndex = index < 0 ? 0 : index);
    if (index < 0) return;
    final (begin, end) = _searchMatches[index];
    if (!begin.attached || !end.attached) return;
    _currentHighlight = _terminalController.highlight(
      p1: begin,
      p2: end,
      color: _colors.brightYellow.withValues(alpha: 0.55),
    );
    if (reveal) _revealRow(begin.y);
  }

  /// Scrolls [row] to the middle of the viewport.
  void _revealRow(int row) {
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (render == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target =
        (row * render.lineHeight -
                position.viewportDimension / 2 +
                render.lineHeight / 2)
            .clamp(0.0, position.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  void _enqueue(Uint8List data) {
    if (data.isEmpty) return;
    _pendingBytes.addLast(data);
    _scheduleDrain(immediate: true);
  }

  /// The first drain after idle goes out on a microtask so an echoed
  /// keystroke still lands in the same frame. Continuations go through the
  /// event loop instead, giving the frame that was just scheduled a chance
  /// to actually render before more parsing starts.
  void _scheduleDrain({required bool immediate}) {
    if (_drainScheduled) return;
    _drainScheduled = true;
    if (immediate) {
      scheduleMicrotask(_drain);
    } else {
      Timer.run(_drain);
    }
  }

  /// Ends the pass exactly where the replay does - live output queued
  /// behind it would otherwise be parsed in the same `_terminal.write` and
  /// take the replay's suppression with it. The write itself still runs
  /// while [_replayBytesLeft] covers these bytes, so the handlers it
  /// reaches can tell replayed sequences from live ones.
  void _drain() {
    _drainScheduled = false;
    if (!mounted || _pendingBytes.isEmpty || !_terminalSized) return;

    final clock = Stopwatch()..start();
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
      if (clock.elapsed >= _drainBudget) break;
    }

    if (_decoded.isNotEmpty) {
      final text = _decoded.toString();
      _decoded.clear();
      _terminal.write(text);
    }

    if (replaying) _replayBytesLeft -= fed;

    if (_pendingBytes.isNotEmpty) _scheduleDrain(immediate: false);
  }

  void focusTerminal() {
    _focusNode.requestFocus();
    _terminalViewKey.currentState?.requestKeyboard();
  }

  void blurTerminal() {
    _terminalViewKey.currentState?.closeKeyboard();
    _focusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void setFontSize(double size) {
    final value = size.clamp(8.0, 24.0);
    if ((_fontSize - value).abs() < 0.001) return;
    setState(() {
      _fontSize = value;
      _scalePreviewFontSize = null;
    });
  }

  void setFontFamily(String fontFamily) {
    if (_fontFamily == fontFamily) return;
    setState(() => _fontFamily = fontFamily);
  }

  void setLineHeight(double lineHeight) {
    final value = lineHeight.clamp(1.0, 2.0);
    if ((_lineHeight - value).abs() < 0.001) return;
    setState(() => _lineHeight = value);
  }

  void setSidePadding(double padding) {
    final value = padding.clamp(0.0, 16.0);
    if ((_sidePadding - value).abs() < 0.001) return;
    setState(() => _sidePadding = value);
  }

  void setColors(app_theme.TerminalColorScheme colors) {
    setState(() => _colors = colors);
  }

  void setCursorStyle(String style) {
    if (_cursorStyle == style) return;
    setState(() => _cursorStyle = style);
  }

  void setPredictiveEcho(bool enabled) {
    _predictiveEcho.enabled = enabled;
  }

  void setCursorBlink(bool blink) {
    if (_cursorBlink == blink) return;
    setState(() => _cursorBlink = blink);
  }

  /// The blink itself lives in the render object: rebuilding the whole
  /// terminal twice a second only to swap one color meant re-measuring the
  /// font and dropping every cached glyph on each tick.
  Duration? get _blinkInterval =>
      _cursorBlink ? const Duration(milliseconds: 600) : null;

  void requestFit() {
    final renderObject = _terminalViewKey.currentState?.renderTerminal;
    renderObject?.markNeedsLayout();
  }

  void refreshTerminal() {
    _terminalViewKey.currentState?.renderTerminal.markNeedsPaint();
  }

  void scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  String? get selectedText {
    final selection = _terminalController.selection;
    if (selection == null) return null;
    return _terminal.buffer.getText(selection);
  }

  void clearSelection() => _terminalController.clearSelection();

  void copySelection() {
    final text = selectedText;
    if (text == null || text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  /// `OSC 52 ; Pc ; Pd` - the remote side asking for the clipboard.
  ///
  /// Writes are honoured with a snackbar, so the host can never swap the
  /// clipboard out from under the user unannounced. Reads (`Pd` is `?`) are
  /// always refused: answering one would hand the server whatever the user
  /// last copied.
  ///
  /// Suppressed during replay: that copy already happened, once, live.
  void _handlePrivateOSC(String ps, List<String> args) {
    if (ps != '52' || args.length < 2) return;
    if (_replayBytesLeft > 0) return;
    final payload = args[1];
    if (payload == '?' || payload.isEmpty) return;

    final String text;
    try {
      text = utf8.decode(base64.decode(payload), allowMalformed: true);
    } on FormatException {
      return;
    }
    if (text.isEmpty) return;

    unawaited(Clipboard.setData(ClipboardData(text: text)));
    if (!mounted) return;
    AppNotifications.info(
      context,
      Translations.of(context).terminal.remoteCopied,
    );
  }

  void _onSelectionChanged() {
    final selection = _terminalController.selection;
    if (selection == null) {
      widget.onSelectionStateChanged?.call(false, 0, 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _terminalController.selection != null) return;
        setState(() => _selection = null);
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final geometry = _measureSelection();
      if (geometry == null) return;
      setState(() => _selection = geometry);
      final stackDy = _renderOriginInStack().dy;
      widget.onSelectionStateChanged?.call(
        true,
        geometry.begin.dy + stackDy,
        geometry.end.dy + geometry.lineHeight + stackDy,
      );
    });
  }

  /// `RenderTerminal`'s origin within this widget's own coordinate space.
  /// `TerminalView` applies the side padding as a `Container` that wraps the
  /// render object, so `RenderTerminal`'s local (0, 0) is not this widget's
  /// (0, 0) - selection handles and the copy/paste popup are positioned in
  /// this widget's Stack, so their coordinates need this added back in, or
  /// they land short by the side padding.
  Offset _renderOriginInStack() {
    final render = _terminalViewKey.currentState?.renderTerminal;
    final ancestor = context.findRenderObject();
    if (render == null || !render.attached || ancestor == null) {
      return Offset.zero;
    }
    return render.localToGlobal(Offset.zero, ancestor: ancestor);
  }

  /// The cursor cell's top-left corner, one line down so a menu anchored
  /// here sits below the cursor rather than on top of it - same coordinate
  /// space [_renderOriginInStack] puts the selection popup in.
  Rect? _cursorRectInStack() {
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (render == null || !render.attached) return null;
    final origin = render.cursorOffset + _renderOriginInStack();
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      render.cellSize.width,
      render.lineHeight,
    );
  }

  Offset? _cursorOffsetInStack() {
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (render == null || !render.attached) return null;
    return render.cursorOffset +
        Offset(0, render.lineHeight) +
        _renderOriginInStack();
  }

  /// Pixel positions of the current selection's ends, in the coordinate space
  /// of the render object. Null when nothing is selected or the terminal has
  /// not been laid out yet.
  _SelectionGeometry? _measureSelection() {
    final selection = _terminalController.selection?.normalized;
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (selection == null || render == null) return null;
    return _SelectionGeometry(
      begin: render.getOffset(selection.begin),
      end: render.getOffset(selection.end),
      beginCell: selection.begin,
      endCell: selection.end,
      lineHeight: render.lineHeight,
      cellWidth: render.cellSize.width,
    );
  }

  /// Handles are positioned in pixels, so they have to follow the scroll.
  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    widget.onScrollModeChanged?.call(
      position.pixels < position.maxScrollExtent - 1,
    );
    if (_selection == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selection == null) return;
      final geometry = _measureSelection();
      if (geometry != null) setState(() => _selection = geometry);
    });
  }

  /// The center of [cell] in render coordinates - the point to feed back into
  /// [RenderTerminal.selectCharacters] as the fixed end of the selection.
  Offset _cellCenter(RenderTerminal render, CellOffset cell) =>
      render.getOffset(cell) +
      Offset(render.cellSize.width / 2, render.lineHeight / 2);

  /// Dragging one handle keeps the opposite end anchored. The end offset
  /// is exclusive, so step back half a cell to land on the last selected
  /// cell.
  void _onHandleDragStart(bool isBegin) {
    final geometry = _selection;
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (geometry == null || render == null) return;
    _dragAnchorCell = isBegin
        ? render.getCellOffset(
            geometry.end +
                Offset(-geometry.cellWidth / 2, geometry.lineHeight / 2),
          )
        : geometry.beginCell;
  }

  void _onHandleDragUpdate(DragUpdateDetails details) {
    final render = _terminalViewKey.currentState?.renderTerminal;
    final anchor = _dragAnchorCell;
    if (render == null || anchor == null) return;
    final local = render.globalToLocal(details.globalPosition);
    _dragLocal = local;
    render.selectCharacters(_cellCenter(render, anchor), local);
    final geometry = _measureSelection();
    if (geometry != null) setState(() => _selection = geometry);
    _autoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _autoScrollTick(),
    );
  }

  /// Belt and braces: a pane torn down mid-drag never gets the pointer-up.
  void _onHandleDragEnd() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _dragLocal = null;
    _dragAnchorCell = null;
    terminalSelectionDragActive.value = false;
  }

  /// While a handle is held near the top or bottom edge, keep scrolling the
  /// scrollback and extending the selection towards it.
  void _autoScrollTick() {
    final local = _dragLocal;
    final anchor = _dragAnchorCell;
    final render = _terminalViewKey.currentState?.renderTerminal;
    if (local == null || anchor == null || render == null) return;
    if (!_scrollController.hasClients) return;

    final lineHeight = render.lineHeight;
    final edge = lineHeight * 1.5;
    final height = render.size.height;
    final delta = local.dy < edge
        ? -lineHeight
        : local.dy > height - edge
        ? lineHeight
        : 0.0;
    if (delta == 0) return;

    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.jumpTo(target);

    render.selectCharacters(_cellCenter(render, anchor), local);
    final geometry = _measureSelection();
    if (geometry != null) setState(() => _selection = geometry);
  }

  /// A tap on a link leaves the keyboard as it was: raising it would push the
  /// link out from under its preview, and so would closing it. The view
  /// raises it on this same tap, right after this, so focus is shut off
  /// until the next frame; [_onPointerUp] has already queued its blur.
  void _onTapUp(TapUpDetails details, CellOffset offset) {
    if (offset.y >= _terminal.buffer.lines.length) return;
    final (first, line) = _lineAround(_terminal.buffer, offset.y);
    final url = linkAt(line, offset.y - first, offset.x);
    if (url == null) return;
    _tapWasLink = true;
    if (!_focusNode.hasFocus) {
      _focusNode.canRequestFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.canRequestFocus = true;
      });
    }
    widget.onLinkDetected?.call(url, details.localPosition.dy);
  }

  int? _tapPointer;
  Offset _tapDownPosition = Offset.zero;
  bool _tapDownKeyboardUp = false;
  bool _tapWasLink = false;

  bool get _isKeyboardVisible {
    final view = View.maybeOf(context);
    if (view != null && view.viewInsets.bottom > 0) return true;
    final mediaInsets = MediaQuery.maybeViewInsetsOf(context);
    if (mediaInsets != null && mediaInsets.bottom > 0) return true;
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_tapPointer != null) {
      _tapPointer = null;
      return;
    }
    _tapPointer = event.pointer;
    _tapDownPosition = event.position;
    _tapDownKeyboardUp = _isKeyboardVisible;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _tapPointer) return;
    if ((event.position - _tapDownPosition).distance > kTouchSlop) {
      _tapPointer = null;
    }
  }

  /// The view requests the keyboard on this same pointer, so this closes
  /// it after.
  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _tapPointer) return;
    _tapPointer = null;
    _tapWasLink = false;
    if (!_tapDownKeyboardUp) return;
    if (_terminalController.selection != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tapWasLink) return;
      blurTerminal();
    });
  }

  TerminalTheme get _terminalTheme => TerminalTheme(
    cursor: _colors.cursor,
    selection: _colors.selection,
    foreground: _colors.foreground,
    background: _colors.background,
    black: _colors.black,
    red: _colors.red,
    green: _colors.green,
    yellow: _colors.yellow,
    blue: _colors.blue,
    magenta: _colors.magenta,
    cyan: _colors.cyan,
    white: _colors.white,
    brightBlack: _colors.brightBlack,
    brightRed: _colors.brightRed,
    brightGreen: _colors.brightGreen,
    brightYellow: _colors.brightYellow,
    brightBlue: _colors.brightBlue,
    brightMagenta: _colors.brightMagenta,
    brightCyan: _colors.brightCyan,
    brightWhite: _colors.brightWhite,
    searchHitBackground: _colors.selection,
    searchHitBackgroundCurrent: _colors.cursor,
    searchHitForeground: _colors.background,
  );

  TerminalCursorType get _terminalCursorType => switch (_cursorStyle) {
    'bar' => TerminalCursorType.verticalBar,
    'underline' => TerminalCursorType.underline,
    _ => TerminalCursorType.block,
  };

  /// The search bar stands above the terminal and takes its own height,
  /// rather than lying over the top rows: what a search most often finds is
  /// in the lines just printed, and on a short screen those were exactly the
  /// ones under the bar. The terminal is a few rows shorter while it is open.
  ///
  /// The column is there whether or not the bar is, so the terminal keeps
  /// its place in the tree - and its state - as the bar comes and goes.
  @override
  Widget build(BuildContext context) {
    final terminal = LayoutBuilder(
      builder: (context, constraints) => _build(context, constraints.maxHeight),
    );
    return Column(
      children: [
        if (_searchOpen)
          TerminalSearchBar(
            controller: _searchField,
            focusNode: _searchFocus,
            total: _searchMatches.length,
            current: _searchIndex,
            caseSensitive: _searchCaseSensitive,
            onChanged: (_) => _runSearch(reveal: true),
            onToggleCase: () {
              _searchCaseSensitive = !_searchCaseSensitive;
              _runSearch(reveal: true);
            },
            onOlder: () => _stepSearch(-1),
            onNewer: () => _stepSearch(1),
            onClose: _closeSearch,
          ),
        Expanded(child: terminal),
      ],
    );
  }

  /// All the bundled font fallback options are Nerd Font variants - same
  /// monospace glyphs as the plain font, plus the Powerline/Devicons/icon
  /// glyph sets full-screen TUIs rely on. Nerd Fonts patches in specific
  /// icon sets, not general Unicode symbol blocks though, so plain symbols
  /// like the media glyphs (⏵⏸⏹, U+23xx) still miss - verified with
  /// `hb-shape` that Hack Nerd Font Mono has no glyph for them at all;
  /// "Noto Sans Symbols2" is what actually covers that block.
  ///
  /// Bottom padding leaves a little breathing room below the last line, or
  /// the prompt sits flush against the toolbar right below it, and scales
  /// with line height so a looser setting actually loosens the bottom edge
  /// too, not just the gaps between lines above it. Focus (and the
  /// keyboard with it) should only ever come from an explicit tap on the
  /// terminal, never from mounting, reconnecting or switching tabs, so
  /// `autofocus` stays off. The tap-toggles-keyboard overlay is a
  /// `Listener`, not a detector, so the view's own tap recogniser wins the
  /// arena against it.
  Widget _build(BuildContext context, double availableHeight) {
    final view = TerminalView(
      _terminal,
      key: _terminalViewKey,
      controller: _terminalController,
      scrollController: _scrollController,
      onSelectionDragChanged: (active) =>
          terminalSelectionDragActive.value = active,
      focusNode: _focusNode,
      theme: _terminalTheme,
      textStyle: TerminalStyle(
        fontSize: _fontSize,
        height: _lineHeight,
        fontFamily: _fontFamily,
        fontFamilyFallback: const [
          'Roboto Mono',
          'Noto Sans Symbols2',
          'Menlo',
          'Monaco',
          'Consolas',
          'Liberation Mono',
          'Courier New',
          'Noto Sans Mono CJK SC',
          'Noto Sans Mono CJK TC',
          'Noto Sans Mono CJK KR',
          'Noto Sans Mono CJK JP',
          'Noto Sans Mono CJK HK',
          'Noto Color Emoji',
          'Noto Sans Symbols',
          'monospace',
          'sans-serif',
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        _sidePadding,
        0,
        _sidePadding,
        terminalBottomPadding(
          availableHeight: availableHeight,
          lineHeight: _lineHeight,
          cellHeight: _fontSize * _lineHeight,
        ),
      ),
      autofocus: false,
      deleteDetection: true,
      keyboardType: TextInputType.text,
      keyboardAppearance: Brightness.dark,
      cursorType: _terminalCursorType,
      blinkInterval: _blinkInterval,
      simulateScroll: true,
      onTapUp: _onTapUp,
      foregroundPainter: _linkUnderlines(
        _terminal,
        _colors.foreground.withValues(alpha: 0.6),
      ),
    );
    final selection = _selection;

    return ColoredBox(
      color: _colors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: (_) => _tapPointer = null,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (_) {
                  _scaleStartFontSize = _fontSize;
                  _scalePreviewFontSize = null;
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2) return;
                  final value = (_scaleStartFontSize * details.scale).clamp(
                    8.0,
                    24.0,
                  );
                  final preview = _scalePreviewFontSize ?? _fontSize;
                  if ((preview - value).abs() < 0.01) return;
                  setState(() => _scalePreviewFontSize = value);
                },
                onScaleEnd: (_) {
                  final value = _scalePreviewFontSize;
                  if (value == null) return;
                  setState(() {
                    _fontSize = value;
                    _scalePreviewFontSize = null;
                  });
                  widget.onFontSizeChanged?.call(value);
                },
                child: Transform.scale(
                  scale: (_scalePreviewFontSize ?? _fontSize) / _fontSize,
                  child: view,
                ),
              ),
            ),
          ),

          if (selection != null) ...[
            _buildSelectionHandle(
              isBegin: true,
              anchor:
                  selection.begin.translate(0, selection.lineHeight) +
                  _renderOriginInStack(),
            ),
            _buildSelectionHandle(
              isBegin: false,
              anchor:
                  selection.end.translate(0, selection.lineHeight) +
                  _renderOriginInStack(),
            ),
          ],
        ],
      ),
    );
  }

  /// A draggable selection handle sitting just below the line it belongs to,
  /// with its pointed corner touching [anchor].
  ///
  /// Wrapped in a [Listener] rather than relying on the gesture detector
  /// alone: pointer events walk the hit-test path inwards first, so this
  /// runs before the swipe's listener further up the tree ever sees the
  /// touch.
  Widget _buildSelectionHandle({
    required bool isBegin,
    required Offset anchor,
  }) {
    const touchSize = 40.0;
    const knobSize = 18.0;
    const radius = Radius.circular(knobSize);
    return Positioned(
      left: anchor.dx - (isBegin ? touchSize : 0),
      top: anchor.dy,
      child: Listener(
        onPointerDown: (_) => terminalSelectionDragActive.value = true,
        onPointerUp: (_) => terminalSelectionDragActive.value = false,
        onPointerCancel: (_) => terminalSelectionDragActive.value = false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _onHandleDragStart(isBegin),
          onPanUpdate: _onHandleDragUpdate,
          onPanEnd: (_) => _onHandleDragEnd(),
          onPanCancel: _onHandleDragEnd,
          child: SizedBox.square(
            dimension: touchSize,
            child: Align(
              alignment: isBegin ? Alignment.topRight : Alignment.topLeft,
              child: Container(
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  color: _colors.cursor,
                  borderRadius: BorderRadius.only(
                    topLeft: isBegin ? radius : Radius.zero,
                    topRight: isBegin ? Radius.zero : radius,
                    bottomLeft: radius,
                    bottomRight: radius,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _scaleStartFontSize = 12;
  double? _scalePreviewFontSize;
}

class _SelectionGeometry {
  const _SelectionGeometry({
    required this.begin,
    required this.end,
    required this.beginCell,
    required this.endCell,
    required this.lineHeight,
    required this.cellWidth,
  });

  /// Top-left pixel of the first selected cell.
  final Offset begin;

  /// Top-left pixel of the cell just past the last selected one.
  final Offset end;

  final CellOffset beginCell;
  final CellOffset endCell;
  final double lineHeight;
  final double cellWidth;
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

/// Underlines the web addresses on the rows in view, so it shows what a tap
/// would open. `terminal_view` draws no underline of its own.
TerminalForegroundPainter _linkUnderlines(Terminal terminal, Color color) =>
    (canvas, origin, render, first, last) {
      final lineHeight = render.lineHeight;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      var y = first;
      while (y <= last) {
        final (top, line) = _lineAround(terminal.buffer, y);
        final spans = linkSpans(line);
        for (var i = 0; i < line.length; i++) {
          final row = top + i;
          if (row < first || row > last) continue;
          for (final (start, end) in spans[i]) {
            final from = origin + render.getOffset(CellOffset(start, row));
            final to = origin + render.getOffset(CellOffset(end, row));
            final baseline = from.dy + lineHeight - 1.5;
            canvas.drawLine(
              Offset(from.dx, baseline),
              Offset(to.dx, baseline),
              paint,
            );
          }
        }
        y = top + line.length;
      }
    };

/// The first row of the line [y] belongs to, and the line's slices: a link
/// the terminal's wrap, or a full-screen program's own break, split across
/// rows has to be read across them. A line runs at most [_maxLineRows] either
/// way, so a screen of dump output is not walked whole on every paint.
(int, List<LineSlice>) _lineAround(Buffer buffer, int y) {
  final lines = buffer.lines;
  bool joins(int row) =>
      row > 0 &&
      row < lines.length &&
      continuesLine(
        lines[row - 1].getText(),
        lines[row].getText(),
        wrapped: lines[row].isWrapped,
        prevWrapped: lines[row - 1].isWrapped,
        width: buffer.viewWidth,
      );
  var first = y;
  while (y - first < _maxLineRows && joins(first)) {
    first--;
  }
  var last = y;
  while (last - y < _maxLineRows && joins(last + 1)) {
    last++;
  }
  return (
    first,
    lineSlices(
      [for (var i = first; i <= last; i++) lines[i].getText()],
      [for (var i = first; i <= last; i++) lines[i].isWrapped],
    ),
  );
}

const _maxLineRows = 16;

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

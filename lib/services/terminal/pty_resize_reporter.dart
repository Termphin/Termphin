import 'dart:async';

/// Tells the server the terminal's size once the layout has settled on one.
///
/// The pane is resized by the layout, so it follows the keyboard frame by
/// frame - and every frame of that is a window-change the remote shell acts
/// on, which a full-screen program answers with a full repaint. So the server
/// only hears the size the layout settled on, [settleDelay] after the last
/// change.
///
/// That leaves one case the server never notices: the local terminal passes
/// through a size and comes back to the one the server already has - as it
/// can while the app comes back from the background. The local buffer has
/// been resized twice by then (a shrink in the alternate screen drops the top
/// rows for good), but the pty's size never changed, so the kernel raises no
/// SIGWINCH and the program never repaints over what is left. Settling back
/// on the server's own size therefore sends a one-row nudge first, which the
/// program answers with a repaint at the final size.
class PtyResizeReporter {
  PtyResizeReporter({
    required this.send,
    this.settleDelay = const Duration(milliseconds: 120),
  });

  final void Function(int cols, int rows) send;
  final Duration settleDelay;

  int? _localCols;
  int? _localRows;
  int? _serverCols;
  int? _serverRows;
  Timer? _timer;

  void report(int cols, int rows) {
    if (cols == _localCols && rows == _localRows) return;
    _localCols = cols;
    _localRows = rows;
    _timer?.cancel();
    _timer = Timer(settleDelay, _flush);
  }

  void _flush() {
    final cols = _localCols!;
    final rows = _localRows!;
    if (cols == _serverCols && rows == _serverRows) {
      send(cols, rows > 1 ? rows - 1 : rows + 1);
    }
    _serverCols = cols;
    _serverRows = rows;
    send(cols, rows);
  }

  void dispose() => _timer?.cancel();
}

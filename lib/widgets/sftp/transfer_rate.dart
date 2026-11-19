/// Bytes per second over the last few seconds of a transfer.
///
/// Recent samples only, so the figure follows the connection instead of
/// averaging the whole transfer.
class TransferRateMeter {
  TransferRateMeter({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const window = Duration(seconds: 3);

  final DateTime Function() _clock;
  final List<(DateTime, int)> _samples = [];

  /// Records [bytes] done so far and returns the rate, or null until two
  /// different readings fall inside the window.
  double? sample(int bytes) {
    final now = _clock();
    if (_samples.isEmpty || _samples.last.$2 != bytes) {
      _samples.add((now, bytes));
    }
    _samples.removeWhere((sample) => now.difference(sample.$1) > window);
    if (_samples.length < 2) return null;
    final seconds =
        _samples.last.$1.difference(_samples.first.$1).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    final delta = _samples.last.$2 - _samples.first.$2;
    return delta <= 0 ? null : delta / seconds;
  }

  void reset() => _samples.clear();
}

import 'dart:typed_data';

/// Keys typed while a session is reconnecting, sent once it is back.
///
/// Only text: whatever lands on the other side lands without the user seeing
/// the state it lands in, so nothing that could run, interrupt or move
/// anything is kept - no Enter, no control key, no escape sequence. A chunk
/// carrying any of those is dropped whole, which is what keeps a multi-line
/// paste from arriving as one joined line. Backspace edits what is held here
/// instead of being sent.
class ReconnectInputBuffer {
  /// Past this the typing is not a thought in progress any more.
  static const maxBytes = 1024;

  final _bytes = <int>[];

  bool get isEmpty => _bytes.isEmpty;

  int get length => _bytes.length;

  /// Characters held, for telling the user how much is waiting.
  int get characters => _bytes.where((byte) => byte & 0xc0 != 0x80).length;

  /// Whether [bytes] were taken, as text or as a backspace over held text.
  bool add(List<int> bytes) {
    if (bytes.length == 1 && (bytes[0] == 0x7f || bytes[0] == 0x08)) {
      return _eraseLast();
    }
    if (bytes.isEmpty || !bytes.every(_isText)) return false;
    if (_bytes.length + bytes.length > maxBytes) return false;
    _bytes.addAll(bytes);
    return true;
  }

  Uint8List take() {
    final taken = Uint8List.fromList(_bytes);
    _bytes.clear();
    return taken;
  }

  void clear() => _bytes.clear();

  static bool _isText(int byte) => byte >= 0x20 && byte != 0x7f;

  /// Erases the last character, stepping back over UTF-8 continuation bytes
  /// to find where it starts.
  bool _eraseLast() {
    if (_bytes.isEmpty) return false;
    var start = _bytes.length - 1;
    while (start > 0 && _bytes[start] & 0xc0 == 0x80) {
      start--;
    }
    _bytes.removeRange(start, _bytes.length);
    return true;
  }
}

import 'dart:typed_data';

/// Why a file was judged not to be editable text.
enum BinaryReason {
  /// It is text.
  none,

  /// A NUL byte - the same rule git uses, and the strongest signal there is.
  nulByte,

  /// The bytes are not valid UTF-8, so opening it would rewrite the file with
  /// replacement characters on save.
  invalidUtf8,

  /// Too much of the content is control bytes to be anything readable.
  controlBytes,

  /// UTF-16/UTF-32, which the editor reads and writes as UTF-8 and would
  /// therefore mangle.
  wideEncoding,
}

class TextProbe {
  const TextProbe.text() : isText = true, reason = BinaryReason.none;
  const TextProbe.binary(this.reason) : isText = false;

  final bool isText;
  final BinaryReason reason;
}

/// Bytes below 0x20 that appear in ordinary text files: tab, LF, vertical
/// tab, form feed, CR, and ESC (common in logs with ANSI colour codes).
const _allowedControlBytes = {
  0x09,
  0x0a,
  0x0b,
  0x0c,
  0x0d,
  0x1b,
};

/// Share of control bytes above which the content is treated as binary.
const _controlByteLimit = 0.1;

/// Decides whether [head] - the first few KB of a file - is text that can be
/// opened in the editor and written back without damage.
///
/// [truncated] tells the sniffer that [head] is a prefix of a longer file, so a
/// multi-byte character cut in half at the end is not held against it.
TextProbe probeTextContent(Uint8List head, {bool truncated = false}) {
  if (head.isEmpty) return const TextProbe.text();

  if (_startsWith(head, const [0xff, 0xfe]) ||
      _startsWith(head, const [0xfe, 0xff]) ||
      _startsWith(head, const [0x00, 0x00, 0xfe, 0xff])) {
    return const TextProbe.binary(BinaryReason.wideEncoding);
  }

  var index = _startsWith(head, const [0xef, 0xbb, 0xbf]) ? 3 : 0;
  var controlBytes = 0;
  var scanned = 0;

  while (index < head.length) {
    final byte = head[index];

    if (byte == 0x00) return const TextProbe.binary(BinaryReason.nulByte);

    if (byte < 0x80) {
      if (byte < 0x20 && !_allowedControlBytes.contains(byte)) controlBytes++;
      if (byte == 0x7f) controlBytes++;
      index++;
      scanned++;
      continue;
    }

    final sequenceLength = _utf8SequenceLength(byte);
    if (sequenceLength == 0) {
      return const TextProbe.binary(BinaryReason.invalidUtf8);
    }
    if (index + sequenceLength > head.length) {
      if (truncated) break;
      return const TextProbe.binary(BinaryReason.invalidUtf8);
    }
    for (var offset = 1; offset < sequenceLength; offset++) {
      if (head[index + offset] & 0xc0 != 0x80) {
        return const TextProbe.binary(BinaryReason.invalidUtf8);
      }
    }
    index += sequenceLength;
    scanned++;
  }

  if (scanned > 0 && controlBytes / scanned > _controlByteLimit) {
    return const TextProbe.binary(BinaryReason.controlBytes);
  }
  return const TextProbe.text();
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Length of the UTF-8 sequence [leadByte] starts, or 0 if it cannot start one.
int _utf8SequenceLength(int leadByte) {
  if (leadByte & 0xe0 == 0xc0) return 2;
  if (leadByte & 0xf0 == 0xe0) return 3;
  if (leadByte & 0xf8 == 0xf0) return 4;
  return 0;
}

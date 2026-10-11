import 'dart:typed_data';

class TerminalModeTracker {
  final Map<int, bool> _modes = {};

  _State _state = _State.ground;
  final List<int> _params = [];
  bool _private = false;

  static const _maxSequenceLength = 64;

  void consume(Uint8List bytes) {
    for (final byte in bytes) {
      switch (_state) {
        case _State.ground:
          if (byte == 0x1b) _state = _State.escape;
        case _State.escape:
          if (byte == 0x5b) {
            _state = _State.csi;
            _params.clear();
            _private = false;
          } else if (byte == 0x63) {
            _modes.clear();
            _state = _State.ground;
          } else {
            _state = byte == 0x1b ? _State.escape : _State.ground;
          }
        case _State.csi:
          _csi(byte);
      }
    }
  }

  void _csi(int byte) {
    if (byte == 0x3f && _params.isEmpty && !_private) {
      _private = true;
    } else if (byte >= 0x40 && byte <= 0x7e) {
      if (_private && (byte == 0x68 || byte == 0x6c)) _apply(byte == 0x68);
      _state = _State.ground;
    } else if (byte == 0x1b) {
      _state = _State.escape;
    } else if (_params.length >= _maxSequenceLength) {
      _state = _State.ground;
    } else {
      _params.add(byte);
    }
  }

  void _apply(bool set) {
    for (final part in String.fromCharCodes(_params).split(';')) {
      final mode = int.tryParse(part);
      if (mode != null) _modes[mode] = set;
    }
  }

  Uint8List get restoreSequence {
    if (_modes.isEmpty) return Uint8List(0);
    final out = StringBuffer();
    for (final MapEntry(key: mode, value: set) in _modes.entries) {
      out.write('\x1b[?$mode${set ? 'h' : 'l'}');
    }
    return Uint8List.fromList(out.toString().codeUnits);
  }

  void reset() {
    _modes.clear();
    _params.clear();
    _private = false;
    _state = _State.ground;
  }
}

enum _State { ground, escape, csi }

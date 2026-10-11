import 'dart:async';

import 'package:flutter/foundation.dart';

/// The two things a session reads out of its own output stream.
///
/// Both were private classes at the bottom of `ssh_session_manager.dart`,
/// which already owns transports, tab persistence, agent probes and the
/// remote multiplexer. Parsing bytes is none of those, and neither piece
/// needs anything from the manager in order to be tested.

/// Waits for a reattached session to finish replaying its scrollback.
///
/// The agent marks the end of a replay with an OSC sequence, but a shell with
/// nothing to replay never sends one - so the wait also gives up once the
/// output has been quiet for a moment, and again at a hard deadline. Missing
/// either of those is a tab that never finishes connecting.
class ReplayWaiter {
  ReplayWaiter({required this.enabled});

  final bool enabled;
  final Completer<void> _complete = Completer<void>();
  DateTime? _lastOutputAt;

  /// Whether the agent continued the client's own output instead of
  /// replaying - known once [wait] returns.
  bool resumed = false;

  void onOutput() {
    if (enabled) _lastOutputAt = DateTime.now();
  }

  void onOsc(String payload) {
    if (!enabled || _complete.isCompleted) return;
    if (payload == '5380;termphin-replay-end') {
      _complete.complete();
    } else if (payload == '5380;termphin-resume-end') {
      resumed = true;
      _complete.complete();
    }
  }

  Future<void> wait() async {
    if (!enabled) return;
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!_complete.isCompleted && DateTime.now().isBefore(deadline)) {
      final lastOutputAt = _lastOutputAt;
      if (lastOutputAt != null &&
          DateTime.now().difference(lastOutputAt) >=
              const Duration(milliseconds: 800)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// Pulls OSC sequences out of a terminal byte stream.
///
/// This is how the agent talks back in-band: the working directory, snippet
/// exit codes and the replay marker above all arrive as OSC payloads mixed
/// into ordinary output. Both terminators are accepted (BEL and
/// ESC-backslash), and an unterminated payload is abandoned past
/// [_maxPayload] rather than buffered forever - a binary file catted to the
/// terminal contains the introducer by chance sooner or later.
class OscMarkerTracker {
  OscMarkerTracker(this.onPayload);

  static const int _maxPayload = 256;

  final void Function(String payload) onPayload;
  final StringBuffer _payload = StringBuffer();
  _OscState _state = _OscState.text;

  /// Index, in the chunk being consumed, of the byte that ended the payload
  /// [onPayload] is being handed.
  int get position => _position;
  int _position = 0;

  void consume(Uint8List data) {
    for (var i = 0; i < data.length; i++) {
      final byte = data[i];
      _position = i;
      switch (_state) {
        case _OscState.text:
          if (byte == 0x1b) _state = _OscState.escape;
        case _OscState.escape:
          if (byte == 0x5d) {
            _payload.clear();
            _state = _OscState.osc;
          } else if (byte != 0x1b) {
            _state = _OscState.text;
          }
        case _OscState.osc:
          if (byte == 0x07) {
            _finish();
          } else if (byte == 0x1b) {
            _state = _OscState.oscEscape;
          } else if (_payload.length >= _maxPayload) {
            _reset();
          } else {
            _payload.writeCharCode(byte);
          }
        case _OscState.oscEscape:
          if (byte == 0x5c) {
            _finish();
          } else {
            _payload
              ..writeCharCode(0x1b)
              ..writeCharCode(byte);
            _state = _OscState.osc;
          }
      }
    }
  }

  void _finish() {
    final value = _payload.toString();
    _reset();
    onPayload(value);
  }

  void _reset() {
    _payload.clear();
    _state = _OscState.text;
  }
}

enum _OscState { text, escape, osc, oscEscape }

/// A place in one agent master's output: its epoch, which tells one master's
/// numbering from another's under the same session name, and the offset.
typedef OutputPosition = ({String epoch, int offset});

/// Where a session's output stands in the agent's own numbering, so a
/// reconnect can ask to resume from the next byte instead of replaying.
///
/// The agent sends the position of the byte after its marker; every byte from
/// there on is shell output, counted as it is delivered. Unknown until a
/// marker arrives - an agent that predates positions never sends one.
class OutputOffsetCounter {
  static final _marker = RegExp(r'^5383;termphin-offset;(\d+):(\d+)$');

  OutputPosition? _position;
  int? _countFrom;

  OutputPosition? get position => _position;

  /// For the payload [OscMarkerTracker] reports, with its
  /// [OscMarkerTracker.position].
  void onOsc(String payload, int endIndex) {
    final match = _marker.firstMatch(payload);
    if (match == null) return;
    final offset = int.tryParse(match.group(2)!);
    if (offset == null) return;
    _position = (epoch: match.group(1)!, offset: offset);
    _countFrom = endIndex + 1;
  }

  /// After each chunk has been through the tracker.
  void onChunk(int length) {
    final position = _position;
    if (position == null) return;
    _position = (
      epoch: position.epoch,
      offset: position.offset + length - (_countFrom ?? 0),
    );
    _countFrom = null;
  }
}

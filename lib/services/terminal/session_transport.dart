import 'dart:typed_data';

/// Byte-stream transport underneath a terminal tab - either an SSH session or a
/// local agent process.
abstract interface class SessionTransport {
  Stream<Uint8List> get output;
  bool get isAlive;
  void Function()? onConnectionLost;
  void write(Uint8List data);
  void resizeTerminal(int width, int height);
  Future<void> disconnect();
}

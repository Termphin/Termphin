import 'dart:typed_data';

import 'package:termphin/services/terminal/session_terminal.dart';

/// A session terminal taking its output from [output], the way a session
/// feeds its own, optionally started from [replay].
SessionTerminal terminalFedBy(Stream<Uint8List> output, {Uint8List? replay}) {
  final terminal = SessionTerminal(replay: replay);
  output.listen(terminal.add);
  return terminal;
}

import 'package:flutter/foundation.dart';

/// Whether terminals stamp printable ASCII from a glyph atlas instead of
/// laying it out as text, run by run. Process-wide, so every pane on screen
/// switches together.
///
/// Off unless the build turns it on with
/// `--dart-define=TERMINAL_GLYPH_ATLAS=true`: a phone showed bold text with
/// letters missing from it, gone again once the atlas was drawn anew, and
/// until why is known text is laid out the proven way. [FrameStatsOverlay]
/// and the debug panel flip it at runtime, for comparing.
final ValueNotifier<bool> terminalGlyphAtlas = ValueNotifier(
  const bool.fromEnvironment('TERMINAL_GLYPH_ATLAS'),
);

/// How long a pane has to hold a height before its terminal is resized to
/// it. A keyboard sliding in changes the height on every frame; the grid is
/// resized once, to where it came to rest. Long enough to span the gap
/// between two frames of an animation, short enough not to be noticed after
/// its last one.
const kTerminalResizeSettleDelay = Duration(milliseconds: 90);

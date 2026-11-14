import 'package:flutter/foundation.dart';

/// Whether terminals stamp printable ASCII from a glyph atlas instead of
/// laying it out as text, run by run. Process-wide, so every pane on screen
/// switches together.
///
/// On unless the build turns it off with
/// `--dart-define=TERMINAL_GLYPH_ATLAS=false`, the way back if a device
/// draws it wrong. [FrameStatsOverlay] flips it at runtime, for comparing.
final ValueNotifier<bool> terminalGlyphAtlas = ValueNotifier(
  const bool.fromEnvironment('TERMINAL_GLYPH_ATLAS', defaultValue: true),
);

/// How long a pane has to hold a height before its terminal is resized to
/// it. A keyboard sliding in changes the height on every frame; the grid is
/// resized once, to where it came to rest. Long enough to span the gap
/// between two frames of an animation, short enough not to be noticed after
/// its last one.
const kTerminalResizeSettleDelay = Duration(milliseconds: 90);

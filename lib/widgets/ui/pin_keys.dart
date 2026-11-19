import 'package:flutter/services.dart';

final _numpad = {
  LogicalKeyboardKey.numpad0: '0',
  LogicalKeyboardKey.numpad1: '1',
  LogicalKeyboardKey.numpad2: '2',
  LogicalKeyboardKey.numpad3: '3',
  LogicalKeyboardKey.numpad4: '4',
  LogicalKeyboardKey.numpad5: '5',
  LogicalKeyboardKey.numpad6: '6',
  LogicalKeyboardKey.numpad7: '7',
  LogicalKeyboardKey.numpad8: '8',
  LogicalKeyboardKey.numpad9: '9',
};

/// The PIN digit a key press types - from the number row or the number pad -
/// or null for any other key, so a PIN can be typed wherever one is asked
/// for.
String? pinDigitFor(KeyEvent event) {
  final fromPad = _numpad[event.logicalKey];
  if (fromPad != null) return fromPad;
  final character = event.character;
  if (character != null && RegExp(r'^[0-9]$').hasMatch(character)) {
    return character;
  }
  return null;
}

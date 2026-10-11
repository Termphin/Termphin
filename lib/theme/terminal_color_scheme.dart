import 'package:flutter/material.dart';

/// Background of the terminal chrome. The terminal keeps its own colours
/// rather than following the app palette; built-in schemes and `AppTheme`
/// both read these.
const Color kTerminalChromeBackground = Color(0xFF090D11);

/// Foreground of the terminal chrome.
const Color kTerminalChromeForeground = Color(0xFFF1F5F7);

/// Cursor of the terminal chrome.
const Color kTerminalChromeCursor = Color(0xFF7E929F);

class TerminalColorScheme {
  const TerminalColorScheme({
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
    required this.uiBorder,
    required this.uiSurface,
    required this.uiActiveBorder,
  });

  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final Color black, red, green, yellow, blue, magenta, cyan, white;
  final Color brightBlack, brightRed, brightGreen, brightYellow;
  final Color brightBlue, brightMagenta, brightCyan, brightWhite;
  final Color uiBorder;
  final Color uiSurface;
  final Color uiActiveBorder;

  static String _hex(Color c) {
    return '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
        '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
        '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';
  }

  Map<String, String> toXtermTheme() => {
    'background': _hex(background),
    'foreground': _hex(foreground),
    'cursor': _hex(cursor),
    'cursorAccent': _hex(background),
    'selectionBackground':
        'rgba(${(selection.r * 255).round()},${(selection.g * 255).round()},${(selection.b * 255).round()},0.4)',
    'black': _hex(black),
    'red': _hex(red),
    'green': _hex(green),
    'yellow': _hex(yellow),
    'blue': _hex(blue),
    'magenta': _hex(magenta),
    'cyan': _hex(cyan),
    'white': _hex(white),
    'brightBlack': _hex(brightBlack),
    'brightRed': _hex(brightRed),
    'brightGreen': _hex(brightGreen),
    'brightYellow': _hex(brightYellow),
    'brightBlue': _hex(brightBlue),
    'brightMagenta': _hex(brightMagenta),
    'brightCyan': _hex(brightCyan),
    'brightWhite': _hex(brightWhite),
  };
}

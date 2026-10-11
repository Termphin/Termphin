import 'package:flutter/material.dart';
import 'package:terminal_view/terminal_view.dart';

import '../../theme/theme.dart' as app_theme;

/// A real terminal rendering a canned session, so the scheme, font, size,
/// line height and cursor are previewed by the same renderer that will draw
/// them - not by an approximation that can drift from it.
///
/// Read-only and untouchable: no PTY behind it, no keyboard, no scroll.
class TerminalPreview extends StatefulWidget {
  const TerminalPreview({
    super.key,
    required this.scheme,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.sidePadding,
    required this.cursorStyle,
    required this.cursorBlink,
  });

  final app_theme.TerminalColorScheme scheme;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double sidePadding;
  final String cursorStyle;
  final bool cursorBlink;

  @override
  State<TerminalPreview> createState() => _TerminalPreviewState();
}

/// Nothing in here is interactive - a tap must not focus a terminal that
/// has no session behind it, or open a keyboard for it. The cursor is
/// always shown instead, since no focus ever lands here and an invisible
/// cursor would make the cursor settings being previewed look like they do
/// nothing.
class _TerminalPreviewState extends State<TerminalPreview> {
  late final Terminal _terminal;

  /// Short lines on purpose: the preview box is narrower than a phone screen,
  /// and a wrap in here would read as a rendering fault rather than a wrap.
  static const _sample = [
    '\x1b[32m➜\x1b[0m \x1b[36mtermphin\x1b[0m \x1b[33mgit:(\x1b[31mmain\x1b[33m)\x1b[0m',
    '\$ ls',
    '\x1b[1;34mlib\x1b[0m  \x1b[1;34mtest\x1b[0m  \x1b[32mbuild.sh\x1b[0m  README.md',
    '\$ ./build.sh --release',
    '\x1b[32m✓\x1b[0m 24 passed  \x1b[31m✗\x1b[0m 1 failed',
    '\x1b[33mwarn:\x1b[0m 2 deprecations',
    '\x1b[40m  \x1b[41m  \x1b[42m  \x1b[43m  \x1b[44m  \x1b[45m  \x1b[46m  \x1b[47m  \x1b[0m',
    '\x1b[100m  \x1b[101m  \x1b[102m  \x1b[103m  \x1b[104m  \x1b[105m  \x1b[106m  \x1b[107m  \x1b[0m',
    '\$ ',
  ];

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 64);
    _terminal.write(_sample.join('\r\n'));
  }

  TerminalTheme get _theme {
    final s = widget.scheme;
    return TerminalTheme(
      cursor: s.cursor,
      selection: s.selection,
      foreground: s.foreground,
      background: s.background,
      black: s.black,
      red: s.red,
      green: s.green,
      yellow: s.yellow,
      blue: s.blue,
      magenta: s.magenta,
      cyan: s.cyan,
      white: s.white,
      brightBlack: s.brightBlack,
      brightRed: s.brightRed,
      brightGreen: s.brightGreen,
      brightYellow: s.brightYellow,
      brightBlue: s.brightBlue,
      brightMagenta: s.brightMagenta,
      brightCyan: s.brightCyan,
      brightWhite: s.brightWhite,
      searchHitBackground: s.selection,
      searchHitBackgroundCurrent: s.cursor,
      searchHitForeground: s.background,
    );
  }

  TerminalCursorType get _cursorType => switch (widget.cursorStyle) {
    'bar' => TerminalCursorType.verticalBar,
    'underline' => TerminalCursorType.underline,
    _ => TerminalCursorType.block,
  };

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(app_theme.AppTheme.radiusMd),
      child: ColoredBox(
        color: widget.scheme.background,
        child: IgnorePointer(
          child: TerminalView(
            _terminal,
            theme: _theme,
            textStyle: TerminalStyle(
              fontSize: widget.fontSize,
              height: widget.lineHeight,
              fontFamily: widget.fontFamily,
              fontFamilyFallback: const [
                'Roboto Mono',
                'Noto Sans Symbols2',
                'Liberation Mono',
                'monospace',
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              widget.sidePadding,
              6,
              widget.sidePadding,
              6,
            ),
            readOnly: true,
            autofocus: false,
            alwaysShowCursor: true,
            blinkInterval: widget.cursorBlink
                ? const Duration(milliseconds: 600)
                : null,
            cursorType: _cursorType,
            simulateScroll: false,
          ),
        ),
      ),
    );
  }
}

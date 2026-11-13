import 'dart:convert';

/// A notification a program asked the terminal to show.
///
/// Programs ask in one of three dialects, all of them OSC sequences that
/// print nothing on the screen:
///
/// - `OSC 9 ; body` - iTerm2's. Claude Code sends it when it finishes or is
///   waiting for an answer, with `preferredNotifChannel` set to `iterm2`.
///   ConEmu reuses the number for numbered commands of its own (`9;4;...` is
///   a progress bar), so a body that is only digits is one of those.
/// - `OSC 777 ; notify ; title ; body` - rxvt-unicode's, also Ghostty's and
///   what `termphin notify` sends.
/// - `OSC 99 ; metadata ; payload` - kitty's. Only the one-shot form is read:
///   `p=title` or `p=body` (the default is the title), `e=1` for a base64
///   payload. A notification sent in several parts (`d=0`) is taken from the
///   part that has it all.
class TerminalNotification {
  const TerminalNotification({required this.title, this.body = ''});

  final String title;
  final String body;

  /// Longest title or body kept. A program writing a novel into a banner
  /// gets the start of it.
  static const maxLength = 200;

  /// The notification [code] and [args] of an OSC sequence ask for, or null
  /// when they are not one.
  static TerminalNotification? fromOsc(String code, List<String> args) {
    final notification = switch (code) {
      '9' => _iterm(args),
      '777' => _rxvt(args),
      '99' => _kitty(args),
      _ => null,
    };
    if (notification == null) return null;
    final title = _clean(notification.title);
    final body = _clean(notification.body);
    if (title.isEmpty && body.isEmpty) return null;
    return TerminalNotification(title: title, body: body);
  }

  static TerminalNotification? _iterm(List<String> args) {
    if (args.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(args.first)) return null;
    return TerminalNotification(title: args.join(';'));
  }

  static TerminalNotification? _rxvt(List<String> args) {
    if (args.length < 2 || args.first != 'notify') return null;
    return TerminalNotification(title: args[1], body: args.skip(2).join(';'));
  }

  static TerminalNotification? _kitty(List<String> args) {
    if (args.length < 2) return null;
    final metadata = <String, String>{
      for (final pair in args.first.split(':'))
        if (pair.contains('='))
          pair.substring(0, pair.indexOf('=')): pair.substring(
            pair.indexOf('=') + 1,
          ),
    };
    var payload = args.skip(1).join(';');
    if (metadata['e'] == '1') {
      try {
        payload = utf8.decode(base64.decode(payload), allowMalformed: true);
      } on FormatException {
        return null;
      }
    }
    return switch (metadata['p'] ?? 'title') {
      'title' => TerminalNotification(title: payload),
      'body' => TerminalNotification(title: '', body: payload),
      _ => null,
    };
  }

  /// One line, no control characters, at most [maxLength] characters: what
  /// reaches a banner is text, not whatever escape a program left in it.
  static String _clean(String text) {
    final flat = text
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return flat.length <= maxLength
        ? flat
        : '${flat.substring(0, maxLength - 1)}…';
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalNotification &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'TerminalNotification($title, $body)';
}

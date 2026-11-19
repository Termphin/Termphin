import 'package:clock/clock.dart';

import 'terminal_notification.dart';

/// A notification ready to be posted: who it is for and what it says.
typedef TerminalAlert = ({String sessionId, String title, String body});

/// Decides which of the notifications programs ask for reach the system.
///
/// One in the session already on screen does not: whoever is looking at it
/// has seen what happened. Everything else does - another tab, the app in
/// the background - unless the setting is off. A program that asks again
/// and again (a loop printing `OSC 9`) gets one notification per session
/// every [quietPeriod], and the newest one wins: a notification about a
/// session replaces the one before it rather than stacking up.
///
/// A notification with only a title says what happened but not where, so
/// the machine's name becomes the title and the program's words the body.
///
/// A stop the user watched and then walked away from is not news either: a
/// session last on screen moments ago is held back for [quietSeen] (the
/// agent's quiet notice comes about 8 s after output stops) or
/// [finishedSeen] (its finished notice comes up to about 2 s after a command
/// ends). A program's own notifications are not held back that way.
///
/// [allows] decides per notification: the agent's own come in two kinds with
/// their own switches, a program's own have one. [quoteLines] decides
/// whether the agent's notifications keep the line of output they quote.
class TerminalAlerts {
  TerminalAlerts({
    required this.post,
    required this.allows,
    required this.quoteLines,
    required this.isForeground,
    required this.sessionsOnScreen,
    this.quietPeriod = const Duration(seconds: 3),
    this.quietSeen = const Duration(seconds: 10),
    this.finishedSeen = const Duration(seconds: 4),
  });

  final void Function(TerminalAlert alert) post;
  final bool Function(TerminalNotification notification) allows;
  final bool Function() quoteLines;
  final bool Function() isForeground;
  /// The sessions whose output is on screen: the tab in front, and every
  /// pane beside it in a split.
  final Set<String> Function() sessionsOnScreen;
  final Duration quietPeriod;
  final Duration quietSeen;
  final Duration finishedSeen;

  final _lastPosted = <String, DateTime>{};
  final _lastSeen = <String, DateTime>{};
  Set<String> _visible = const {};

  /// Notes what is on screen now, after the app or the tabs changed. Each
  /// session that was on screen until now and is not any more is stamped as
  /// seen at this moment.
  void visibilityChanged() {
    final visible = isForeground() ? sessionsOnScreen() : const <String>{};
    final now = clock.now();
    for (final left in _visible.difference(visible)) {
      _lastSeen[left] = now;
    }
    _visible = visible;
  }

  void handle({
    required String sessionId,
    required String sessionName,
    required TerminalNotification notification,
  }) {
    if (!allows(notification)) return;
    if (isForeground() && sessionsOnScreen().contains(sessionId)) return;
    final now = clock.now();
    final kind = notification.kind;
    if (kind != null) {
      final seen = _lastSeen[sessionId];
      if (seen != null && now.difference(seen) < _seenWindow(kind)) return;
    }
    final last = _lastPosted[sessionId];
    if (last != null && now.difference(last) < quietPeriod) return;
    _lastPosted[sessionId] = now;

    final body = notification.kind != null && !quoteLines()
        ? notification.plain
        : notification.body;
    final hasBody = body.isNotEmpty;
    post((
      sessionId: sessionId,
      title: hasBody && notification.title.isNotEmpty
          ? notification.title
          : sessionName,
      body: hasBody ? body : notification.title,
    ));
  }

  Duration _seenWindow(TerminalNoticeKind kind) => switch (kind) {
    TerminalNoticeKind.quiet => quietSeen,
    TerminalNoticeKind.finished => finishedSeen,
  };

  /// Forgets [sessionId], whose tab is gone.
  void forget(String sessionId) {
    _lastPosted.remove(sessionId);
    _lastSeen.remove(sessionId);
  }
}

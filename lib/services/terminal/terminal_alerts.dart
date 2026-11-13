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
class TerminalAlerts {
  TerminalAlerts({
    required this.post,
    required this.enabled,
    required this.isForeground,
    required this.activeSessionId,
    this.quietPeriod = const Duration(seconds: 3),
  });

  final void Function(TerminalAlert alert) post;
  final bool Function() enabled;
  final bool Function() isForeground;
  final String? Function() activeSessionId;
  final Duration quietPeriod;

  final _lastPosted = <String, DateTime>{};

  void handle({
    required String sessionId,
    required String sessionName,
    required TerminalNotification notification,
  }) {
    if (!enabled()) return;
    if (isForeground() && activeSessionId() == sessionId) return;
    final now = clock.now();
    final last = _lastPosted[sessionId];
    if (last != null && now.difference(last) < quietPeriod) return;
    _lastPosted[sessionId] = now;

    final hasBody = notification.body.isNotEmpty;
    post((
      sessionId: sessionId,
      title: hasBody && notification.title.isNotEmpty
          ? notification.title
          : sessionName,
      body: hasBody ? notification.body : notification.title,
    ));
  }

  /// Forgets [sessionId], whose tab is gone.
  void forget(String sessionId) => _lastPosted.remove(sessionId);
}

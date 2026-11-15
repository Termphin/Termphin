import 'package:material_ui/material_ui.dart';

import '../settings/terminal_settings.dart';
import 'terminal_alerts.dart';

/// Where a terminal alert goes while Termphin is in front: nowhere, when the
/// user wants no notifications while the app is open; a card inside the
/// app, with a buzz; or the system notification, as in the background.
///
/// [present] is set by the app shell, which owns the overlay the card goes
/// on and knows how to open the session it is about. It answers false when
/// it cannot show one - nothing on screen yet, the PIN screen up, where the
/// card would show what a session printed over the lock - and the caller
/// posts the system notification instead.
class InAppAlerts {
  InAppAlerts({
    required this.isForeground,
    required this.enabled,
    required this.inApp,
  });

  static final instance = InAppAlerts(
    isForeground: () =>
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    enabled: () => terminalSettings.openAppNotices.value,
    inApp: () =>
        terminalSettings.openAppNoticeStyle.value == kOpenAppNoticeInApp,
  );

  final bool Function() isForeground;

  /// [TerminalSettings.openAppNotices].
  final bool Function() enabled;

  /// [TerminalSettings.openAppNoticeStyle] is the app's own card.
  final bool Function() inApp;

  bool Function(TerminalAlert alert)? present;

  /// True when [alert] is taken care of - shown inside the app, or dropped
  /// because the user wants nothing while the app is open - and needs no
  /// system notification.
  bool handle(TerminalAlert alert) {
    if (!isForeground()) return false;
    if (!enabled()) return true;
    final present = this.present;
    if (present == null || !inApp()) return false;
    return present(alert);
  }
}

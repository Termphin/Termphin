import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'models/session_tab.dart';
import 'screens/share/share_screen.dart';
import 'services/account/account_service.dart';
import 'services/analytics/analytics_service.dart';
import 'services/app/app_commands.dart';
import 'services/app/error_reports.dart';
import 'services/app/font_licenses.dart';
import 'services/app/identity_anonymizer.dart';
import 'services/platform/app_updater.dart';
import 'services/platform/desktop_window.dart';
import 'services/platform/foreground_notification_service.dart';
import 'services/platform/ios_background_task.dart';
import 'services/platform/local_notifications_service.dart';
import 'services/pro/pro_hints.dart';
import 'services/pro/pro_service.dart';
import 'services/push/notify_prefs_store.dart';
import 'services/push/push_service.dart';
import 'services/realtime/presence_device.dart';
import 'services/security/secret_cipher.dart';
import 'services/settings/anonymize_setting.dart';
import 'services/settings/app_settings.dart';
import 'services/settings/terminal_settings.dart';
import 'services/ssh/network_monitor.dart';
import 'services/ssh/ssh_prompts.dart';
import 'services/ssh/ssh_session_manager.dart';
import 'services/terminal/in_app_alerts.dart';
import 'services/terminal/terminal_alerts.dart';
import 'services/terminal/terminal_notification.dart';
import 'utils/platform_info.dart';
import 'utils/system_bars.dart';
import 'widgets/ssh/host_key_dialog.dart';
import 'widgets/ssh/keyboard_interactive_dialog.dart';

/// Guard flag to prevent double-initialisation when the Android system
/// re-creates the Activity but keeps the process alive (e.g. after ANR
/// recovery or a configuration change).
bool _mainInitialized = false;

/// App entry point.
///
/// Loads settings before the first frame so a light-theme user never sees a
/// dark one, then restores sessions and the network monitor before `runApp`
/// so the UI has live sessions and connectivity state on first render. A
/// socket bound to an interface that left goes silent rather than erroring,
/// so a handover re-probes sessions instead of waiting out the keepalive.
/// Firebase is not started here: `AnalyticsService.init` starts it only when
/// consent is on record. Analytics capture and crash reports are no-ops until
/// then, so the `appOpened` event can be fired right after `init`.
///
/// On a desktop the window comes up first: the app's own title bar in place
/// of the system's, the window where it was last time, and the keyboard
/// shortcuts. Linux may have no keyring, so it is asked for the master key
/// now rather than on the first save, which lets Settings say so before the
/// user trusts it with a password.
Future<void> main() async {
  if (_mainInitialized) {
    runApp(const SshClientApp());
    return;
  }
  _mainInitialized = true;

  WidgetsFlutterBinding.ensureInitialized();
  await drawBehindSystemBars();
  ErrorReports.instance.install();
  registerFontLicenses();

  await loadAppSettings();
  await ErrorReports.instance.load();

  await DesktopWindow.instance.init();
  AppCommands.instance.install();
  AppUpdater.instance.bindContext(() => navigatorKey.currentContext);
  unawaited(AppUpdater.instance.start());
  if (isLinuxPlatform) unawaited(SecretCipher.instance.masterKey());

  await SshSessionManager.instance.init();
  _bindConnectionPrompts();
  final alerts = _bindTerminalAlerts();
  await ForegroundNotificationService.instance.init();
  _bindForegroundService();
  await NetworkMonitor.instance.init();
  NetworkMonitor.instance.onHandover.listen(
    (_) => SshSessionManager.instance.probeSessions(handover: true),
  );
  AppLifecycleListener(
    onResume: _onResume,
    onPause: _onPause,
    onStateChange: (_) => alerts.visibilityChanged(),
  );

  await AnalyticsService.instance.init();
  AnalyticsService.instance.installErrorHandlers();
  await AccountService.instance.init();
  unawaited(PushService.instance.init());
  _bindPushEnrollment();
  unawaited(_bindDeviceAnnouncement());
  unawaited(AnalyticsService.instance.capture(AnalyticsEvent.appOpened));
  runApp(const SshClientApp());
}

/// Whether a desktop's window has the focus: one behind another app's, or
/// hidden in the tray, still counts as in front for keeping sessions alive,
/// but nobody is looking at it. A phone's app in front is looked at.
bool _windowFocused() =>
    !isDesktopPlatform ||
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

/// Posts what programs ask the terminal to announce, for sessions other than
/// the one on screen; see [TerminalAlerts]. The notifications service is
/// started here rather than on first use so a tap that launched the app is
/// still there to be read.
TerminalAlerts _bindTerminalAlerts() {
  final manager = SshSessionManager.instance;
  final notifications = LocalNotificationsService.instance;
  unawaited(notifications.init());
  final alerts = TerminalAlerts(
    post: (alert) {
      manager.noteUnread(alert.sessionId);
      if (!InAppAlerts.instance.handle(alert)) {
        unawaited(
          notifications.showTerminalAlert(
            sessionId: alert.sessionId,
            title: alert.title,
            body: alert.body,
            source: alert.source,
          ),
        );
      }
      unawaited(ProHints.instance.offer(ProHint.longCommand));
    },
    allows: (notification) => switch (notification.kind) {
      null => terminalSettings.programNotifications.value,
      TerminalNoticeKind.finished =>
        terminalSettings.finishedNotifications.value,
      TerminalNoticeKind.quiet => terminalSettings.quietNotifications.value,
    },
    quoteLines: () => terminalSettings.noticeLines.value,
    isForeground: () => manager.foreground && _windowFocused(),
    sessionsOnScreen: () => manager.sessionsOnScreen,
    seen: (sessionId) {
      unawaited(notifications.cancelTerminalAlert(sessionId));
      final session = manager.getSession(sessionId);
      final name = session?.muxName;
      if (session != null && name != null) {
        unawaited(
          PushService.instance.clearDelivered(session.profile.id, name),
        );
      }
    },
  );
  manager.onTerminalNotification = (session, notification) => alerts.handle(
    sessionId: session.id,
    sessionName: anonymizeSetting.value
        ? IdentityAnonymizer.name(session.profile.id)
        : session.profile.name,
    notification: notification,
    source: switch (session.muxName) {
      final name? => SessionTab.displayName(name),
      null => null,
    },
  );
  manager.addListener(alerts.visibilityChanged);
  return alerts;
}

/// Hands every machine that finishes connecting to [PushService], which
/// gives it a relay key, or takes one away, as the machine's settings say.
/// The service remembers what it set up, so this can fire on every change -
/// and it fires on Pro being confirmed and push being switched on too, since
/// a machine met before either is set up only then.
void _bindPushEnrollment() {
  final manager = SshSessionManager.instance;
  void enroll() {
    for (final session in manager.activeSessions) {
      if (session.isRun ||
          session.dropped ||
          session.connecting ||
          session.sshService == null) {
        continue;
      }
      unawaited(
        PushService.instance.ensureOnServer(
          manager: manager,
          sessionId: session.id,
          profile: session.profile,
        ),
      );
    }
  }

  manager.addListener(enroll);
  ProService.instance.confirmed.addListener(enroll);
  PushService.instance.enabledNotifier.addListener(enroll);
  void syncNotices() => unawaited(PushService.instance.syncNoticePrefs());
  terminalSettings.finishedNotifications.addListener(syncNotices);
  terminalSettings.quietNotifications.addListener(syncNotices);
  terminalSettings.noticeLines.addListener(syncNotices);
  ProService.instance.confirmed.addListener(syncNotices);
}

/// Gives the session manager what to tell agent masters about this device,
/// so the user's other devices can show which sessions are open here. The
/// name is the host name on a computer and the kind of device elsewhere,
/// where the system gives no name without asking for more. The same kind
/// is what this device is listed as among the account's devices for push.
Future<void> _bindDeviceAnnouncement() async {
  final view = PlatformDispatcher.instance.views.firstOrNull;
  final shortestSide = view == null
      ? 0.0
      : view.physicalSize.shortestSide / view.devicePixelRatio;
  final kind = isDesktopPlatform
      ? PresenceDeviceKind.desktop
      : shortestSide >= 600
      ? PresenceDeviceKind.tablet
      : PresenceDeviceKind.phone;
  final name = switch (kind) {
    PresenceDeviceKind.desktop => Platform.localHostname,
    PresenceDeviceKind.tablet => isIOSPlatform ? 'iPad' : 'Android tablet',
    PresenceDeviceKind.phone => isIOSPlatform ? 'iPhone' : 'Android',
  };
  PushService.instance.deviceKind = () => kind == PresenceDeviceKind.tablet
      ? NotifyDeviceKind.tablet
      : NotifyDeviceKind.phone;
  SshSessionManager.instance.deviceDescription = presenceDeviceDescription(
    installId: await PushService.instance.installId(),
    kind: kind,
    name: name,
  );
}

/// What `ShareActivity` runs instead of [main]: an engine of its own that
/// only sends a share to a server, over whatever app it came from. Named in
/// that activity, so it has to survive tree shaking.
@pragma('vm:entry-point')
Future<void> shareMain() => runShareApp();

/// Called when the app returns to the foreground.
///
/// Reloads shared preferences because the share screen runs in its own
/// engine and writes through its own copy (e.g. a host key accepted there).
/// Refreshes the network state before touching sessions: a backgrounded
/// process is frozen, so the keepalive timer never noticed a dead transport
/// and queued connectivity broadcasts were dropped; a stale offline reading
/// would leave sessions with nothing to wake them.
void _onResume() {
  unawaited(SharedPreferences.getInstance().then((prefs) => prefs.reload()));
  unawaited(NetworkMonitor.instance.refresh());
  SshSessionManager.instance.dropDeadSessions();
  SshSessionManager.instance.probeSessions();
  SshSessionManager.instance.setForeground(true);
  if (isIOSPlatform) SshSessionManager.instance.comeBack();
}

/// iOS freezes the app moments after this without closing its connections,
/// so the masters are told the phone went away while there is still time:
/// under a background grant, held a moment so the bytes leave. Android's
/// foreground service keeps the app running and its notifications working,
/// so it says nothing and nothing changes there.
void _onPause() {
  SshSessionManager.instance.setForeground(false);
  if (!isIOSPlatform) return;
  unawaited(
    IOSBackgroundTask.guard('presence', () async {
      SshSessionManager.instance.goAway();
      await Future<void>.delayed(const Duration(seconds: 1));
    }),
  );
}

/// Gives the SSH layer a way to ask the user something mid-handshake.
///
/// Wired here for the same reason as the foreground service below: both
/// answers are Flutter dialogs, and the manager stays platform-neutral. Until
/// this runs, an unrecognised host key has nobody to confirm it and is
/// refused - which is the behaviour we want for anything connecting before
/// the UI exists.
/// One question on screen at a time, however many connections are in flight.
final _connectionPrompts = ConnectionPromptQueue();

void _bindConnectionPrompts() {
  final manager = SshSessionManager.instance;
  manager.hostKeyPrompt = _connectionPrompts.hostKey(showHostKeyPrompt);
  manager.keyboardInteractivePrompt = _connectionPrompts.keyboardInteractive(
    showKeyboardInteractivePrompt,
  );
}

/// Keeps the foreground service running exactly while sessions are connected.
/// Wired here rather than inside the manager so that stays platform-neutral.
void _bindForegroundService() {
  final manager = SshSessionManager.instance;
  void sync() => unawaited(
    ForegroundNotificationService.instance.syncSessions(manager.activeCount),
  );
  manager.addListener(sync);
  sync();
}

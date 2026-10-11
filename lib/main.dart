import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'screens/share/share_screen.dart';
import 'services/analytics/analytics_service.dart';
import 'services/app/app_commands.dart';
import 'services/platform/desktop_window.dart';
import 'services/platform/foreground_notification_service.dart';
import 'services/security/secret_cipher.dart';
import 'services/settings/app_settings.dart';
import 'services/ssh/network_monitor.dart';
import 'services/ssh/ssh_prompts.dart';
import 'services/ssh/ssh_session_manager.dart';
import 'utils/platform_info.dart';
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
/// Analytics capture is a no-op until consent is answered, so the
/// `appOpened` event can be fired right after `init`.
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

  await loadAppSettings();

  await DesktopWindow.instance.init();
  AppCommands.instance.install();
  if (isLinuxPlatform) unawaited(SecretCipher.instance.masterKey());

  await SshSessionManager.instance.init();
  _bindConnectionPrompts();
  await ForegroundNotificationService.instance.init();
  _bindForegroundService();
  await NetworkMonitor.instance.init();
  NetworkMonitor.instance.onHandover.listen(
    (_) => SshSessionManager.instance.probeSessions(handover: true),
  );
  AppLifecycleListener(
    onResume: _onResume,
    onPause: () => SshSessionManager.instance.setForeground(false),
  );

  await AnalyticsService.instance.init();
  unawaited(AnalyticsService.instance.capture(AnalyticsEvent.appOpened));
  runApp(const SshClientApp());
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

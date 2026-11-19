import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';
import 'desktop_window.dart';

/// Local notifications on iOS and on a Linux or Windows desktop, and the
/// notification permission that goes with them.
///
/// Android posts its own: a transfer is reported by `DownloadChannel.kt`
/// alongside the bytes it is writing, and the session notification belongs to
/// the foreground service. Neither has an iOS counterpart, so this is what
/// reports a finished transfer there.
///
/// What it deliberately does not do is announce connected sessions. That
/// notification is Android's price for a foreground service holding the
/// process at foreground importance; iOS has no such API, so within about
/// thirty seconds of leaving the app the sessions it named are gone and the
/// notification would be a claim about nothing. The agent is what survives
/// that, and saying so belongs on a settings row rather than in a banner.
///
/// A desktop gets the terminal alerts and the dropped-session notice: with
/// the window behind others or in the tray, the system notification is the
/// only way a finished job reaches the user, and a click on it brings the
/// window back on that session. Neither Linux nor Windows asks permission.
/// macOS does, and waits for its own permission flow.
class LocalNotificationsService {
  LocalNotificationsService._();

  static final instance = LocalNotificationsService._();

  static const _transferDoneId = 4101;
  static const _transferFailedId = 4102;
  static const _sessionDroppedId = 4103;

  static const _sessionChannelId = 'session_alerts';
  static const _terminalChannelId = 'terminal_alerts';

  /// Notification ids for terminal alerts start here, one per session, so a
  /// session's newest replaces its last instead of stacking up.
  static const _terminalAlertBaseId = 5000;
  static const _sessionPayloadPrefix = 'session:';

  /// Opens the session a tapped notification was about. Set by the app shell
  /// once it can navigate; a tap that launched the app waits for it.
  void Function(String sessionId)? get onOpenSession => _onOpenSession;
  set onOpenSession(void Function(String sessionId)? handler) {
    _onOpenSession = handler;
    final pending = _pendingSessionId;
    if (handler != null && pending != null) {
      _pendingSessionId = null;
      handler(pending);
    }
  }

  void Function(String sessionId)? _onOpenSession;
  String? _pendingSessionId;

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get supported => isIOSPlatform;

  /// Where terminal alerts and the dropped-session notice are posted.
  bool get _postsAlerts =>
      isAndroidPlatform ||
      isIOSPlatform ||
      isLinuxPlatform ||
      isWindowsPlatform;

  /// Identifies Termphin's notifications to Windows; it must never change,
  /// or Windows treats a new install as another app.
  static const _windowsGuid = '38931182-274b-4fd4-950b-cf39410b63fc';
  static const _windowsAppUserModelId = 'Termphin.Termphin';

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Nothing is requested here. Every `request*Permission` is off, so the
  /// prompt is raised by the row the user tapped rather than by a launch they
  /// did not ask a question of. Called at startup, so a plugin that cannot
  /// start leaves the app without notifications rather than failing it.
  Future<void> init() async {
    if (!_postsAlerts) return;
    if (_initialized) return;
    _initialized = true;
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_termphin'),
          iOS: const DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
          linux: LinuxInitializationSettings(
            defaultActionName: t.notifications.openSession,
          ),
          windows: const WindowsInitializationSettings(
            appName: 'Termphin',
            appUserModelId: _windowsAppUserModelId,
            guid: _windowsGuid,
          ),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _openFromPayload(response.payload),
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _openFromPayload(launch!.notificationResponse?.payload);
      }
    } catch (_) {}
  }

  void _openFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_sessionPayloadPrefix)) return;
    if (isDesktopPlatform) unawaited(DesktopWindow.instance.show());
    final sessionId = payload.substring(_sessionPayloadPrefix.length);
    final handler = _onOpenSession;
    if (handler == null) {
      _pendingSessionId = sessionId;
    } else {
      handler(sessionId);
    }
  }

  /// Posts what a program in [sessionId] asked the terminal to announce.
  /// Tapping it opens that session.
  Future<void> showTerminalAlert({
    required String sessionId,
    required String title,
    required String body,
  }) async {
    if (!_postsAlerts) return;
    await _show(
      id: terminalAlertId(sessionId),
      title: title,
      body: body,
      payload: '$_sessionPayloadPrefix$sessionId',
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          _terminalChannelId,
          t.notifications.terminalChannelName,
          channelDescription: t.notifications.terminalChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(presentBadge: false),
      ),
    );
  }

  /// The notification id of [sessionId]'s alerts: the same id every time,
  /// so the newest replaces the last.
  static int terminalAlertId(String sessionId) =>
      _terminalAlertBaseId + (sessionId.hashCode & 0xfff);

  Future<bool> hasPermission() async {
    if (isIOSPlatform) {
      final options = await _ios?.checkPermissions();
      return options?.isEnabled ?? false;
    }
    if (isAndroidPlatform) {
      try {
        final enabled = await _android?.areNotificationsEnabled();
        return enabled ?? false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// A permission already answered cannot be asked for again, and the request
  /// resolves false without showing anything - so a refusal sends the user to
  /// the system's own screen, which is the only place the switch still exists.
  Future<bool> requestPermission() async {
    if (!supported) return true;
    await init();
    final granted = await _ios?.requestPermissions(alert: true, sound: true);
    if (granted ?? false) return true;
    if (await hasPermission()) return true;
    await openSettings();
    return false;
  }

  Future<void> openSettings() async {
    if (!supported) return;
    await _ios?.openAppNotificationSettings();
  }

  /// [fileCount] above one means a folder or a multi-entry selection, which
  /// reads as a count rather than as one of the names.
  Future<void> showTransferComplete({
    required String fileName,
    required int fileCount,
    bool isUpload = false,
  }) async {
    if (!supported) return;
    final title = isUpload
        ? t.notifications.uploadDoneTitle
        : t.notifications.transferDoneTitle;
    final body = switch ((isUpload, fileCount > 1)) {
      (true, true) => t.notifications.uploadDoneMany(
        count: fileCount,
        folder: fileName,
      ),
      (true, false) => t.notifications.uploadDoneOne(name: fileName),
      (false, true) => t.notifications.transferDoneMany(
        count: fileCount,
        folder: fileName,
      ),
      (false, false) => t.notifications.transferDoneOne(name: fileName),
    };
    await _show(id: _transferDoneId, title: title, body: body);
  }

  Future<void> showTransferFailed({
    required String fileName,
    bool isUpload = false,
  }) async {
    if (!supported) return;
    await _show(
      id: _transferFailedId,
      title: isUpload
          ? t.notifications.uploadFailedTitle
          : t.notifications.transferFailedTitle,
      body: t.notifications.transferFailedBody(name: fileName),
    );
  }

  Future<void> showSessionDropped({required String name}) async {
    if (!_postsAlerts) return;
    await _show(
      id: _sessionDroppedId,
      title: t.notifications.sessionDroppedTitle,
      body: t.notifications.sessionDroppedBody(name: name),
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          _sessionChannelId,
          t.notifications.sessionChannelName,
          channelDescription: t.notifications.sessionChannelDescription,
          importance: Importance.defaultImportance,
        ),
        iOS: const DarwinNotificationDetails(presentBadge: false),
      ),
    );
  }

  /// Posting without the permission throws on iOS, and a notification must not
  /// fail over the way it was announced. There is nothing to fall back to on
  /// any other failure either - the in-app toast has already said it.
  Future<void> _show({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationDetails? details,
  }) async {
    await init();
    if (!await hasPermission()) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails:
            details ??
            const NotificationDetails(
              iOS: DarwinNotificationDetails(presentBadge: false),
            ),
      );
    } catch (_) {}
  }
}

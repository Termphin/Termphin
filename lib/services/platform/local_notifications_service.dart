import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';

/// Local notifications on iOS, and the notification permission that goes with
/// them.
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
class LocalNotificationsService {
  LocalNotificationsService._();

  static final instance = LocalNotificationsService._();

  static const _transferDoneId = 4101;
  static const _transferFailedId = 4102;
  static const _sessionDroppedId = 4103;

  static const _sessionChannelId = 'session_alerts';

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get supported => isIOSPlatform;

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
  /// did not ask a question of.
  Future<void> init() async {
    if (!isAndroidPlatform && !isIOSPlatform) return;
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_termphin'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

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
  }) async {
    if (!supported) return;
    await _show(
      id: _transferDoneId,
      title: t.notifications.transferDoneTitle,
      body: fileCount > 1
          ? t.notifications.transferDoneMany(count: fileCount, folder: fileName)
          : t.notifications.transferDoneOne(name: fileName),
    );
  }

  Future<void> showTransferFailed({required String fileName}) async {
    if (!supported) return;
    await _show(
      id: _transferFailedId,
      title: t.notifications.transferFailedTitle,
      body: t.notifications.transferFailedBody(name: fileName),
    );
  }

  Future<void> showSessionDropped({required String name}) async {
    if (!isAndroidPlatform && !isIOSPlatform) return;
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
    NotificationDetails? details,
  }) async {
    await init();
    if (!await hasPermission()) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails:
            details ??
            const NotificationDetails(
              iOS: DarwinNotificationDetails(presentBadge: false),
            ),
      );
    } catch (_) {}
  }
}

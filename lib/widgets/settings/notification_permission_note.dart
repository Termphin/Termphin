import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/platform/foreground_notification_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/info_note.dart';
import '../ui/permission_tile.dart';

/// A warning above the notification settings while the system keeps
/// Termphin's notifications from showing, since every setting under it does
/// nothing until they are allowed. A tap asks for the permission, or opens
/// the system's screen once it can no longer be asked for.
///
/// The system answers nothing back when the user changes it there, so the
/// state is read again whenever the app comes back to the front. Nothing is
/// drawn while it is unknown or granted.
class NotificationPermissionNote extends StatefulWidget {
  const NotificationPermissionNote({
    super.key,
    this.hasPermission,
    this.requestPermission,
  });

  /// Defaults to [ForegroundNotificationService.hasNotificationPermission].
  final Future<bool> Function()? hasPermission;

  /// Defaults to [ForegroundNotificationService.requestNotificationPermission].
  final Future<bool> Function()? requestPermission;

  @override
  State<NotificationPermissionNote> createState() =>
      _NotificationPermissionNoteState();
}

class _NotificationPermissionNoteState extends State<NotificationPermissionNote>
    with WidgetsBindingObserver, _WatchesPermission {
  @override
  Future<bool> Function()? get _check => widget.hasPermission;

  @override
  Future<bool> Function()? get _request => widget.requestPermission;

  @override
  Widget build(BuildContext context) {
    if (_granted ?? true) return const SizedBox.shrink();
    final t = Translations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space16),
      child: Semantics(
        button: true,
        child: InfoNote(
          t.settings.notificationsBlocked,
          tone: InfoNoteTone.warning,
          action: t.settings.notificationsBlockedAction,
          onTap: _allow,
        ),
      ),
    );
  }
}

/// The notification permission as a row, at the foot of the notification
/// settings: allowed, a tap opens the system's own page for Termphin's
/// notifications, where sound, banners and the lock screen are set; not
/// allowed, a tap asks, the same as [NotificationPermissionNote] above.
class NotificationPermissionRow extends StatefulWidget {
  const NotificationPermissionRow({
    super.key,
    this.hasPermission,
    this.requestPermission,
    this.openSettings,
  });

  /// Defaults to [ForegroundNotificationService.hasNotificationPermission].
  final Future<bool> Function()? hasPermission;

  /// Defaults to [ForegroundNotificationService.requestNotificationPermission].
  final Future<bool> Function()? requestPermission;

  /// Defaults to [ForegroundNotificationService.openNotificationSettings].
  final Future<void> Function()? openSettings;

  @override
  State<NotificationPermissionRow> createState() =>
      _NotificationPermissionRowState();
}

class _NotificationPermissionRowState extends State<NotificationPermissionRow>
    with WidgetsBindingObserver, _WatchesPermission {
  @override
  Future<bool> Function()? get _check => widget.hasPermission;

  @override
  Future<bool> Function()? get _request => widget.requestPermission;

  Future<void> _onTap() async {
    if (_granted ?? false) {
      final open =
          widget.openSettings ??
          ForegroundNotificationService.instance.openNotificationSettings;
      await open();
      await _refresh();
    } else {
      await _allow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final granted = _granted ?? true;
    return AppCard(
      child: PermissionTile(
        leading: Icon(
          granted ? PhosphorIconsRegular.bell : PhosphorIconsRegular.bellSlash,
          color: granted ? context.colors.primary : context.colors.warning,
        ),
        title: t.settings.notificationsPermission,
        subtitle: t.settings.notificationsPermissionSubtitle,
        granted: granted,
        onTap: _onTap,
      ),
    );
  }
}

/// The permission as last read, read again whenever the app comes back to
/// the front: the system answers nothing back when the user changes it on
/// its own screen.
mixin _WatchesPermission<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  Future<bool> Function()? get _check;
  Future<bool> Function()? get _request;

  /// `null` until the first answer.
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final check =
        _check ??
        () => ForegroundNotificationService.instance.hasNotificationPermission;
    final granted = await check();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _allow() async {
    final request =
        _request ??
        ForegroundNotificationService.instance.requestNotificationPermission;
    await request();
    await _refresh();
  }
}

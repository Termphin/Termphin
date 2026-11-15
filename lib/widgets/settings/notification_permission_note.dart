import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/platform/foreground_notification_service.dart';
import '../../theme/theme.dart';
import '../ui/info_note.dart';

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
    with WidgetsBindingObserver {
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
        widget.hasPermission ??
        () => ForegroundNotificationService.instance.hasNotificationPermission;
    final granted = await check();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _allow() async {
    final request =
        widget.requestPermission ??
        ForegroundNotificationService.instance.requestNotificationPermission;
    await request();
    await _refresh();
  }

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

import 'package:flutter/foundation.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/ssh_profile.dart';
import '../../widgets/ssh/session_status.dart';
import '../app/identity_anonymizer.dart';

/// One row of the tray's menu, whichever system draws it.
@immutable
class TrayMenuEntry {
  const TrayMenuEntry({
    required this.label,
    this.onSelected,
    this.enabled = true,
    this.children = const [],
  }) : separator = false;

  const TrayMenuEntry.separator()
    : label = '',
      onSelected = null,
      enabled = false,
      children = const [],
      separator = true;

  final String label;
  final VoidCallback? onSelected;
  final bool enabled;

  /// A submenu; the entry itself then does nothing when picked.
  final List<TrayMenuEntry> children;
  final bool separator;
}

/// How many machines "New session" offers - the ones used last.
const kTrayRecentMachines = 5;

/// The tray's menu: the window, the sessions connected right now, a new
/// session on a recent machine, and quitting.
///
/// Only connected sessions. A detached one is parked on its server on
/// purpose, and the tray is for what is running here.
List<TrayMenuEntry> buildTrayMenu({
  required Translations t,
  required List<ActiveSessionView> connected,
  required List<SshProfile> profiles,
  required bool anonymize,
  required VoidCallback onShow,
  required void Function(ActiveSessionView session) onOpenSession,
  required void Function(SshProfile profile) onNewSession,
  required VoidCallback onQuit,
}) {
  String machine(SshProfile profile) =>
      anonymize ? IdentityAnonymizer.name(profile.id) : profile.name;

  final recent = [...profiles]
    ..sort((a, b) {
      final at = a.lastConnectedAt;
      final bt = b.lastConnectedAt;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

  return [
    TrayMenuEntry(label: t.window.trayShow, onSelected: onShow),
    const TrayMenuEntry.separator(),
    if (connected.isEmpty)
      TrayMenuEntry(label: t.window.trayNoSessions, enabled: false)
    else
      for (final session in connected)
        TrayMenuEntry(
          label:
              '${machine(session.profile)} - '
              '${sessionDisplayName(session, anonymize: anonymize)}',
          onSelected: () => onOpenSession(session),
        ),
    if (recent.isNotEmpty) ...[
      const TrayMenuEntry.separator(),
      TrayMenuEntry(
        label: t.window.trayNewSession,
        children: [
          for (final profile in recent.take(kTrayRecentMachines))
            TrayMenuEntry(
              label: machine(profile),
              onSelected: () => onNewSession(profile),
            ),
        ],
      ),
    ],
    const TrayMenuEntry.separator(),
    TrayMenuEntry(label: t.commands.quit, onSelected: onQuit),
  ];
}

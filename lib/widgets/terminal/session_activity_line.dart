import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/live_presence_provider.dart';
import '../../services/realtime/presence_state.dart';
import '../../theme/theme.dart';

/// The session [muxName] on the machine [profileId] as its agent last
/// reported it; null when that is not known here.
PresenceSession? reportedSessionOf(
  Map<String, ServerPresence> presence,
  String profileId,
  String? muxName,
) {
  if (muxName == null) return null;
  return presence[profileId]?.sessions
      ?.where((session) => session.name == muxName)
      .firstOrNull;
}

/// What the session [muxName] on the machine [profileId] is doing, from
/// what its agent last reported; null when that is not known here.
SessionActivity? sessionActivityOf(
  Map<String, ServerPresence> presence,
  String profileId,
  String? muxName,
) => reportedSessionOf(presence, profileId, muxName)?.activity;

/// What a session is doing, under its name, as its agent last reported it:
/// `npm run build · Working`, or `claude · Waiting for you` in the warning
/// colour, which is the one worth looking at; "Restores when opened" for one
/// a reboot stopped. Nothing for a session at its prompt, nor when the
/// server's state cannot be read here.
///
/// A command can name a host or a user, so with [anonymizeProvider] on only
/// the state is shown.
class SessionActivityLine extends ConsumerWidget {
  const SessionActivityLine({
    super.key,
    required this.profileId,
    required this.muxName,
  });

  final String profileId;
  final String? muxName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reported = reportedSessionOf(
      ref.watch(livePresenceProvider),
      profileId,
      muxName,
    );
    final t = Translations.of(context);
    final colors = context.colors;
    if (reported != null && reported.restorable) {
      return Padding(
        padding: const EdgeInsets.only(top: AppTheme.space2),
        child: Text(
          t.session.restoresWhenOpened,
          key: const ValueKey('sessionActivity'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: colors.uiSmall.copyWith(color: colors.textTertiary),
        ),
      );
    }
    final activity = reported?.activity;
    if (activity == null || activity.state == SessionActivityState.idle) {
      return const SizedBox.shrink();
    }
    final state = switch (activity.state) {
      SessionActivityState.working => t.session.activityWorking,
      SessionActivityState.waiting => t.session.activityWaiting,
      SessionActivityState.running ||
      SessionActivityState.idle => t.session.activityRunning,
    };
    final command = ref.watch(anonymizeProvider) ? null : activity.command;
    final waiting = activity.state == SessionActivityState.waiting;
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.space2),
      child: Text(
        command == null
            ? state
            : t.session.activityLine(command: command, state: state),
        key: const ValueKey('sessionActivity'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: colors.uiSmall.copyWith(
          color: waiting ? colors.warning : colors.textTertiary,
          fontWeight: waiting ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

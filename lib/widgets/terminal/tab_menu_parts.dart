import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../services/ssh/connection_quality.dart';
import '../../theme/theme.dart';
import '../profiles/profile_avatar.dart';
import '../ui/segmented_switch.dart';
import 'session_view.dart';

/// Icon for each view a tab's menu or badge can show, filled for the active
/// one and outlined otherwise.
const modeIcons = {
  SessionViewMode.terminal: (
    PhosphorIconsFill.terminalWindow,
    PhosphorIconsRegular.terminalWindow,
  ),
  SessionViewMode.sftp: (
    PhosphorIconsFill.folderOpen,
    PhosphorIconsRegular.folderOpen,
  ),
};

/// What switching to [mode] is called, for a tooltip or a menu item.
String modeLabel(Translations t, SessionViewMode mode) => switch (mode) {
  SessionViewMode.terminal => t.terminal.switchToTerminal,
  SessionViewMode.sftp => t.terminal.switchToSftp,
};

/// Whose tab the menu belongs to: the machine, where it logs in, and how
/// quickly it answers.
class TabMenuHeader extends StatelessWidget {
  const TabMenuHeader({
    super.key,
    required this.profile,
    required this.name,
    required this.address,
    required this.quality,
  });

  final SshProfile profile;
  final String name;
  final String address;
  final ConnectionQuality? quality;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quality = this.quality;
    return Row(
      children: [
        ProfileAvatar(
          iconName: profile.iconName,
          colorHex: profile.colorHex,
          size: 30,
        ),
        const SizedBox(width: AppTheme.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: colors.itemTitle.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTheme.space2),
              Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: colors.monoSmall,
              ),
            ],
          ),
        ),
        if (quality != null)
          ListenableBuilder(
            listenable: quality,
            builder: (context, _) {
              final latency = quality.recentLatency;
              if (latency == null) return const SizedBox.shrink();
              return LatencyPill(ms: latency, health: quality.health);
            },
          ),
      ],
    );
  }
}

/// A connection's latency, coloured by how healthy it is.
class LatencyPill extends StatelessWidget {
  const LatencyPill({super.key, required this.ms, required this.health});

  final int ms;
  final ConnectionHealth health;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (color, background) = switch (health) {
      ConnectionHealth.good => (colors.success, colors.successHighlight),
      ConnectionHealth.slow => (colors.warning, colors.warningHighlight),
      ConnectionHealth.unresponsive => (colors.error, colors.errorHighlight),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space8,
        vertical: AppTheme.space4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppTheme.space6,
            height: AppTheme.space6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppTheme.space6),
          Text(
            Translations.of(context).session.latency(ms: ms),
            style: colors.uiSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detaching and ending, stacked at the foot of the menu. A session
/// that is not persistent only has the one way out.
///
/// Close (the way out that keeps everything) is styled to be the one to
/// reach for. The menu is a route of its own: an action closes it first,
/// then runs, the same order a picked entry goes in.
class TabMenuLeave extends StatelessWidget {
  const TabMenuLeave({
    super.key,
    required this.sessionId,
    required this.closeLabel,
    required this.closeIcon,
    required this.endLabel,
    required this.onClose,
    this.onEndSession,
  });

  final String sessionId;
  final String closeLabel;
  final IconData closeIcon;
  final String? endLabel;
  final VoidCallback onClose;
  final VoidCallback? onEndSession;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    void run(VoidCallback action) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => action());
    }

    final endLabel = this.endLabel;
    final onEndSession = this.onEndSession;
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              key: ValueKey('tabMenuItem-$sessionId-close'),
              onPressed: () => run(onClose),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
              ),
              icon: Icon(closeIcon, size: AppTheme.icon18),
              label: Text(
                closeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (endLabel != null && onEndSession != null) ...[
            const SizedBox(height: AppTheme.space8),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                key: ValueKey('tabMenuItem-$sessionId-endSession'),
                onPressed: () => run(onEndSession),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.surfaceBorderStrong),
                ),
                icon: const Icon(
                  PhosphorIconsRegular.trash,
                  size: AppTheme.icon18,
                ),
                label: Text(
                  endLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Terminal and SFTP side by side, inside the tab's menu.
///
/// Icons only: there are two of them, they are the same two icons the tab
/// strip already labels the view with, and words wide enough to read forced
/// each half narrower than a comfortable tap. Each half is the full height of
/// the control, so the target is the segment rather than the glyph in it.
class ViewModeSegments extends StatelessWidget {
  const ViewModeSegments({
    super.key,
    required this.sessionId,
    required this.mode,
    required this.onSelect,
  });

  final String sessionId;
  final SessionViewMode mode;
  final ValueChanged<SessionViewMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return SegmentedSwitch<SessionViewMode>(
      thumbKey: const ValueKey('viewModeThumb'),
      selected: mode,
      segments: [
        for (final candidate in SessionViewMode.values)
          SwitchSegment(
            key: ValueKey('viewModeSegment-$sessionId-${candidate.name}'),
            value: candidate,
            icon: modeIcons[candidate]!.$1,
            tooltip: modeLabel(t, candidate),
            label: switch (candidate) {
              SessionViewMode.terminal => t.terminal.modeTerminal,
              SessionViewMode.sftp => t.terminal.modeFiles,
            },
          ),
      ],
      onChanged: (picked) {
        Navigator.of(context).pop();
        onSelect(picked);
      },
    );
  }
}

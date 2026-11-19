import 'package:material_ui/material_ui.dart';

import '../../models/session_tab.dart';
import '../../models/ssh_profile.dart';
import '../../theme/theme.dart';
import '../profiles/profile_avatar.dart';
import 'notice_dot.dart';

/// Type size and line height inside a tab; the strip's height is derived from
/// these, so they live with the pill rather than in a second place.
const double kSessionTabNameSize = 13.0;
const double kSessionTabLineHeight = 1.25;

/// Vertical padding inside a tab pill.
const double kSessionTabPillPaddingY = 6.0;

/// One session as the strip draws it: the machine's avatar in a ring that says
/// how the connection is, then "session - machine", then whatever [trailing]
/// the caller puts at the end - the strip's view-mode badge and menu.
///
/// Shared so a session looks the same wherever it is listed: in the
/// terminal's strip, and in the desktop's sidebar while no session is on
/// screen. Two hand-drawn versions of one row drifted apart the first time.
class SessionTabPill extends StatelessWidget {
  const SessionTabPill({
    super.key,
    required this.sessionId,
    required this.profile,
    required this.statusColor,
    required this.displayName,
    required this.onTap,
    this.sessionName,
    this.isActive = false,
    this.collapsed = false,
    this.unread = false,
    this.stretch = true,
    this.trailing = const [],
  });

  final String sessionId;
  final SshProfile profile;

  /// The ring around the avatar: green connected, amber on its way, red
  /// failed, plain when there is nothing to say.
  final Color statusColor;

  /// The machine's name as shown - already anonymized where it has to be.
  final String displayName;

  /// The persistent session's name, which leads the label when there is one.
  final String? sessionName;
  final VoidCallback onTap;
  final bool isActive;

  /// Avatar only, for a collapsed rail - the ring still says the status.
  final bool collapsed;

  /// A notification came from this session since it was last on screen.
  final bool unread;

  /// Fills the rail's width rather than sizing to the label.
  final bool stretch;
  final List<Widget> trailing;

  /// The label is one line: without `maxLines` a long name wraps and nothing
  /// beside it lines up; in the rail it also pushes the trailing controls to
  /// its right edge.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBg = theme.colorScheme.surface;
    final activeBorder = theme.dividerColor;
    final activeText = theme.colorScheme.onSurface;
    final inactiveText = activeText.withValues(alpha: 0.55);

    final ring = AnimatedContainer(
      key: ValueKey('sessionStatusAvatar-$sessionId'),
      duration: AppTheme.interactiveDuration,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: statusColor, width: 1.25),
      ),
      padding: const EdgeInsets.all(AppTheme.space2),
      child: ProfileAvatar(
        iconName: profile.iconName,
        colorHex: profile.colorHex,
        size: 20,
      ),
    );
    final avatar = NoticeDot(
      visible: unread,
      ground: Theme.of(context).scaffoldBackgroundColor,
      child: ring,
    );

    final name = _name(isActive ? activeText : inactiveText);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        key: ValueKey('sessionTabContent-$sessionId'),
        duration: AppTheme.motionFast,
        padding: EdgeInsets.only(
          left: collapsed ? AppTheme.space4 : AppTheme.space14,
          right: AppTheme.space4,
          top: kSessionTabPillPaddingY,
          bottom: kSessionTabPillPaddingY,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? Color.alphaBlend(
                  context.colors.primary.withValues(alpha: 0.06),
                  activeBg,
                )
              : activeBg.invisible,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: isActive ? activeBorder : activeBorder.invisible,
            width: 1,
          ),
        ),
        child: collapsed
            ? Center(child: avatar)
            : Row(
                mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  avatar,
                  const SizedBox(width: AppTheme.space8),
                  if (stretch)
                    Expanded(child: name)
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: name,
                    ),
                  const SizedBox(width: AppTheme.space6),
                  ...trailing,
                ],
              ),
      ),
    );
  }

  Widget _name(Color color) {
    final session = sessionName;
    return Text.rich(
      TextSpan(
        children: [
          if (session != null) ...[
            TextSpan(text: SessionTab.displayName(session)),
            TextSpan(
              text: ' - $displayName',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          ] else
            TextSpan(text: displayName),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: kSessionTabNameSize,
        height: kSessionTabLineHeight,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
        color: color,
      ),
    );
  }
}

/// The square buttons beside the tabs - add a session, back on a phone.
class StripActionButton extends StatelessWidget {
  const StripActionButton({
    super.key,
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  /// On the button's own surface, where the strip's tests look for it.
  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      side: BorderSide(color: active ? colors.primary : colors.surfaceBorder),
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        key: buttonKey,
        color: active ? colors.primaryHighlight : colors.surfaceOffset,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(
              icon,
              size: AppTheme.icon18,
              color: active ? colors.primary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

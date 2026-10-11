import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/session_tab.dart';
import '../../models/ssh_profile.dart';
import '../../providers/ssh_connection_provider.dart' show ConnectionStatus;
import '../../theme/theme.dart';
import '../profiles/profile_avatar.dart';
import '../ui/app_dropdown.dart';
import 'session_view.dart';
import 'tab_menu_parts.dart';

/// Type size of a tab's name, and the line height it is set at. The strip's
/// own height is derived from these in `terminalTabBarHeight` rather than
/// written down separately - two numbers that have to agree but are declared
/// apart only agree until one of them is edited.
const kTabNameSize = 13.0;
const kTabLineHeight = 1.25;

/// Vertical padding inside a tab pill.
const kTabPillPaddingY = 6.0;

/// One tab's pill: the avatar ringed in its connection status, the name, the
/// view-mode badge and the overflow menu.
///
/// Collapsed, there is room for the avatar and nothing else, which still
/// carries the status ring so what a tab says about its connection
/// survives the collapse; the rest moves into the tooltip - the only thing
/// left that can tell two tabs apart once the name and the server are gone
/// from the rail. That tooltip's trigger is manual rather than long-press:
/// a long press on a tab is how it is picked up and reordered, and a
/// tooltip that also answers to one would win that gesture off the rail's
/// list, so collapsed tabs could not be dragged at all - hovering still
/// shows it, and it is still what a screen reader announces.
///
/// The name reads "session - server": the session name tells two shells on
/// the same host apart, the server name trails it dimmer. `maxLines`
/// matters as much as the ellipsis: without it a long name wraps and
/// everything beside it stops lining up with the text, and in the rail it
/// also pushes the status badge and menu button all the way to its right
/// edge instead of leaving them stranded right after a short name.
class TerminalTabPill<T> extends StatelessWidget {
  const TerminalTabPill({
    super.key,
    required this.sessionId,
    required this.profile,
    required this.status,
    required this.sessionName,
    required this.displayName,
    required this.mode,
    required this.isActive,
    required this.stretch,
    this.collapsed = false,
    required this.menuItems,
    required this.onTap,
    required this.onMenuAction,
  });

  final String sessionId;
  final SshProfile profile;
  final ConnectionStatus status;

  /// The persistent session's own name, when it has one - `null` otherwise.
  final String? sessionName;
  final String displayName;
  final SessionViewMode mode;
  final bool isActive;
  final bool stretch;
  final bool collapsed;

  final List<DropdownItem<T>> menuItems;
  final VoidCallback onTap;
  final ValueChanged<T> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final activeBg = Theme.of(context).colorScheme.surface;
    final activeBorder = Theme.of(context).dividerColor;
    final activeText = Theme.of(context).colorScheme.onSurface;
    final inactiveText = activeText.withValues(alpha: 0.55);
    final statusBorderColor = switch (status) {
      ConnectionStatus.connected => context.colors.success,
      ConnectionStatus.connecting ||
      ConnectionStatus.reconnecting => context.colors.warning,
      ConnectionStatus.error => context.colors.error,
      ConnectionStatus.disconnected => activeBorder,
    };
    final avatar = AnimatedContainer(
      key: ValueKey('sessionStatusAvatar-$sessionId'),
      duration: AppTheme.interactiveDuration,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: statusBorderColor, width: 1.25),
      ),
      padding: const EdgeInsets.all(1),
      child: ProfileAvatar(
        iconName: profile.iconName,
        colorHex: profile.colorHex,
        size: 20,
      ),
    );

    final tab = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        key: ValueKey('sessionTabContent-$sessionId'),
        duration: AppTheme.motionFast,
        padding: EdgeInsets.only(
          left: collapsed ? 4 : 14,
          right: 4,
          top: kTabPillPaddingY,
          bottom: kTabPillPaddingY,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  avatar,
                  const SizedBox(width: 8),
                  if (stretch)
                    Expanded(child: _buildName(activeText, inactiveText))
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: _buildName(activeText, inactiveText),
                    ),
                  const SizedBox(width: 6),
                  if (status == ConnectionStatus.connected)
                    ViewModeBadge(
                      key: ValueKey('viewModeBadge-$sessionId'),
                      mode: mode,
                      idleColor: isActive
                          ? activeText.withValues(alpha: 0.6)
                          : inactiveText,
                    ),
                  AppActionDropdown<T>(
                    key: ValueKey('tabMenu-$sessionId'),
                    iconColor: isActive
                        ? activeText.withValues(alpha: 0.7)
                        : inactiveText,
                    width: 280,
                    items: menuItems,
                    onSelected: onMenuAction,
                  ),
                ],
              ),
      ),
    );

    if (!collapsed) return tab;
    final sessionName = this.sessionName;
    return Tooltip(
      message: sessionName != null
          ? '${SessionTab.displayName(sessionName)} - $displayName'
          : displayName,
      triggerMode: TooltipTriggerMode.manual,
      child: tab,
    );
  }

  Widget _buildName(Color activeText, Color inactiveText) {
    final sessionName = this.sessionName;
    return Text.rich(
      TextSpan(
        children: [
          if (sessionName != null) ...[
            TextSpan(text: SessionTab.displayName(sessionName)),
            TextSpan(
              text: ' - $displayName',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: (isActive ? activeText : inactiveText).withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ] else
            TextSpan(text: displayName),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: kTabNameSize,
        height: kTabLineHeight,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
        color: isActive ? activeText : inactiveText,
      ),
    );
  }
}

/// Says which of the two views a tab is on, and nothing more.
///
/// Deliberately not a button: it sits right beside the tab's menu, and a tap
/// target that close to another one is as likely to be hit by accident as on
/// purpose. Switching is the segmented control inside that menu.
class ViewModeBadge extends StatelessWidget {
  const ViewModeBadge({super.key, required this.mode, required this.idleColor});

  final SessionViewMode mode;

  /// Same weight whichever view the tab is on - it reports state, it is not
  /// an alert, and accenting one of two ordinary modes only makes the strip
  /// look like something needs attention.
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Tooltip(
      message: modeLabel(t, mode),
      child: SizedBox.square(
        dimension: 20,
        child: Center(
          child: AnimatedSwitcher(
            duration: AppTheme.motionFast,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              modeIcons[mode]!.$1,
              key: ValueKey(mode),
              size: 15,
              color: idleColor,
            ),
          ),
        ),
      ),
    );
  }
}

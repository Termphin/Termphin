import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/sidebar_settings.dart';
import '../../theme/theme.dart';

/// Width of a wide-layout side rail with its labels showing.
const double kNavRailWidth = 240;

/// Width of the same rail collapsed to icons only - one icon plus the
/// padding either side of it, and nothing else. Wide enough that a 20pt icon
/// still sits in a 48pt tap target rather than against the edges.
const double kNavRailCollapsedWidth = 64;

double navRailWidth(bool collapsed) =>
    collapsed ? kNavRailCollapsedWidth : kNavRailWidth;

/// The hamburger that collapses either rail, and the only writer of
/// [sidebarCollapsedSetting].
///
/// Both rails draw it themselves rather than sharing a header widget: the nav
/// rail has nothing else along the top, and the terminal's rail has to stand
/// it next to the back button it already had.
class NavRailToggleButton extends StatelessWidget {
  const NavRailToggleButton({super.key, required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
    );
    return Tooltip(
      message: collapsed ? t.nav.expandSidebar : t.nav.collapseSidebar,
      child: Material(
        color: context.colors.backgroundPrimary.invisible,
        shape: shape,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            unawaited(sidebarCollapsedSetting.set(!collapsed));
          },
          customBorder: shape,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              PhosphorIconsRegular.list,
              size: 20,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination of the app's own navigation - Machines, Snippets, Keys,
/// Settings - as both rails draw it.
class ShellNavItem {
  const ShellNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// A destination's row in a side rail. Shared by `MainShell`'s sidebar and the
/// terminal's: on a desktop they are the same strip with the same rows at the
/// top, so the terminal is a place in the navigation rather than a screen
/// over it that has to be backed out of.
class SidebarNavItem extends StatelessWidget {
  const SidebarNavItem({
    super.key,
    required this.data,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final ShellNavItem data;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// Collapsed, the icon is all there is to go on, so the label it replaced
  /// stays reachable as a tooltip.
  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.colors.primary
        : context.colors.textSecondary;
    final icon = Icon(
      selected ? data.selectedIcon : data.icon,
      size: 20,
      color: foreground,
    );

    final Widget button = Material(
      color: context.colors.backgroundPrimary.invisible,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          curve: AppTheme.interactiveCurve,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 14,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.primaryHighlight
                : context.colors.primaryHighlight.invisible,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: collapsed
              ? Center(child: icon)
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        data.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.uiStyle.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: data.label, child: button) : button;
  }
}

/// The small caption over the sessions in a desktop rail. Nothing collapsed:
/// a hairline says the same without words.
class SidebarSectionLabel extends StatelessWidget {
  const SidebarSectionLabel(this.label, {super.key, required this.collapsed});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Divider(height: 1, color: context.colors.surfaceDivider),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: context.colors.uiSmall.copyWith(
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}

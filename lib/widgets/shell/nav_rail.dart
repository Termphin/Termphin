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
              size: AppTheme.icon20,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

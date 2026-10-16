import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import 'settings_tile.dart';

/// A row for something the system owns, not the app: the state is read from
/// the system and the tap only takes the user to where it can be changed. A
/// switch would be a lie - flipping it back off is not something the app can
/// do. Built on SettingsTile with a trailing status text instead of the
/// standard chevron.
class PermissionTile extends StatelessWidget {
  const PermissionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
    this.leading,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback? onTap;
  final Widget? leading;

  /// Onboarding packs two of these into a card; Settings gives them the same
  /// room as every other row there.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return SettingsTile(
      title: title,
      leading: leading,
      subtitle: subtitle,
      onTap: onTap,
      trailing: SettingsTileTrailing.none,
      trailingWidget: Text(
        granted ? t.common.allowed : t.common.allow,
        style: TextStyle(
          fontSize: AppTheme.font13,
          fontWeight: FontWeight.w600,
          color: granted ? context.colors.success : context.colors.primary,
        ),
      ),
      dense: dense,
    );
  }
}

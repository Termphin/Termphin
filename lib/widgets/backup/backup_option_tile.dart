import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import '../ui/settings_tile.dart';

/// One switchable section of a backup, on the export screen and in the import
/// sheet alike - the two halves of the same job, so they are drawn by the same
/// row rather than by a card on one side and a bare checkbox on the other.
class BackupOptionTile extends StatelessWidget {
  const BackupOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.sensitive = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;

  /// Paints the icon in the warning colour while on - the sections that put
  /// credentials in the file.
  final bool sensitive;
  final ValueChanged<bool>? onChanged;

  /// Sits under the row, inside the same tap target's column - the per-entry
  /// list the import sheet expands.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSwitchTile(
          icon: icon,
          iconColor: sensitive && value
              ? context.colors.warning
              : enabled
              ? null
              : context.colors.textTertiary,
          title: title,
          subtitle: subtitle,
          dense: true,
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
        ?trailing,
      ],
    );
  }
}

class BackupWarningBanner extends StatelessWidget {
  const BackupWarningBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space14,
        vertical: AppTheme.space10,
      ),
      decoration: BoxDecoration(
        color: context.colors.warning.withAlpha(28),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.warning.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsFill.warning,
            size: AppTheme.icon18,
            color: context.colors.warning,
          ),
          const SizedBox(width: AppTheme.space10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppTheme.font12,
                color: context.colors.warning,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

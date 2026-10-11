import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';

/// A row for something the system owns, not the app: the state is read from
/// Android and the tap only takes the user to where it can be changed. A
/// switch would be a lie - flipping it back off is not something the app can
/// do.
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: leading,
      title: Text(title, style: TextStyle(fontSize: dense ? 14 : null)),
      subtitle: Text(
        subtitle,
        style:
            (dense
                    ? Theme.of(context).textTheme.bodySmall
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(color: context.colors.textTertiary),
      ),
      trailing: Text(
        granted ? t.common.allowed : t.common.allow,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: granted ? context.colors.success : context.colors.primary,
        ),
      ),
      onTap: onTap,
    );
  }
}

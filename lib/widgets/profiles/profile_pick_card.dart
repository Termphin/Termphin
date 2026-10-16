import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import '../ui/app_card.dart';

/// The card a machine picker draws for one candidate: an elevated [AppCard]
/// with [leading], [title], optional [subtitle] and a selection indicator.
///
/// Shared between the jump host sheet and the snippet run screen's machine
/// picker, which had each grown an identical card - same fill, same border
/// that turns to the accent when picked, same avatar and title styles - with
/// only the trailing indicator drifting apart: [showUnselectedIndicator]
/// keeps the snippet run list's always-visible circle, while the jump host
/// sheet leaves it off by default.
class ProfilePickCard extends StatelessWidget {
  const ProfilePickCard({
    super.key,
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.showUnselectedIndicator = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Draws a hollow circle beside a row that is not picked yet, instead of
  /// leaving its trailing edge blank.
  final bool showUnselectedIndicator;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      elevated: true,
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.space14),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppTheme.space14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.itemTitle,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: colors.uiStyle,
                  ),
                ],
              ],
            ),
          ),
          if (selected || showUnselectedIndicator) ...[
            const SizedBox(width: AppTheme.space8),
            Icon(
              selected
                  ? PhosphorIconsRegular.checkCircle
                  : PhosphorIconsRegular.circle,
              size: AppTheme.icon20,
              color: selected ? colors.primary : colors.textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';

/// Always the last thing stitched under a machine, connected and detached
/// sessions alike - a dedicated way to start a fresh session without having
/// to repurpose a tap on the card or on one of its existing rows.
class NewSessionRow extends StatelessWidget {
  const NewSessionRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return AppCard.segment(
      first: false,
      last: true,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16,
        AppTheme.space10,
        AppTheme.space16,
        AppTheme.space10,
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.plus,
            size: AppTheme.icon16,
            color: context.colors.primary,
          ),
          const SizedBox(width: AppTheme.space12),
          Text(
            t.terminal.newSession,
            style: context.colors.uiStyle.copyWith(
              fontSize: AppTheme.font13,
              fontWeight: FontWeight.w600,
              color: context.colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

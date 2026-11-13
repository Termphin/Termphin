import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../screens/settings/account_screen.dart';
import '../../services/account/account_service.dart';
import '../../theme/theme.dart';

/// The account, in the corner of the machine list: the first letter of the
/// signed-in address, or an empty silhouette inviting a sign-in. Opens the
/// account screen either way. Absent from a build that cannot have
/// accounts.
class AccountAvatarButton extends ConsumerWidget {
  const AccountAvatarButton({super.key});

  /// The letter that stands for [user]: the first of their name or address.
  static String initialOf(AccountUser user) {
    final source = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email ?? '').trim();
    return source.isEmpty ? '?' : source.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AccountService.instance.available) return const SizedBox.shrink();
    final t = Translations.of(context);
    final user = ref.watch(accountProvider);
    final anonymize = ref.watch(anonymizeProvider);
    final colors = context.colors;
    return IconButton(
      tooltip: t.account.title,
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
      icon: user == null
          ? Icon(
              PhosphorIconsRegular.userCircle,
              size: AppTheme.icon28,
              color: colors.textSecondary,
            )
          : Container(
              width: AppTheme.icon28,
              height: AppTheme.icon28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                anonymize ? '•' : initialOf(user),
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: AppTheme.font14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }
}

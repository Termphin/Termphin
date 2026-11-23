import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../screens/settings/account_screen.dart';
import '../../services/account/account_service.dart';
import '../../theme/theme.dart';
import '../ui/section_navigator.dart';
import 'account_avatar.dart';

/// The account, in the corner of the machine list: the first letter of the
/// signed-in address, or an empty silhouette inviting a sign-in. Opens the
/// account screen either way. Absent from a build that cannot have
/// accounts.
///
/// Not an `IconButton`: that centres the avatar in a 48-wide target flush
/// with the bar's edge, which left it 6 dp from the screen edge while every
/// card under it keeps 16. The padding here puts its edge on the cards'.
class AccountAvatarButton extends ConsumerWidget {
  const AccountAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AccountService.instance.available) return const SizedBox.shrink();
    final t = Translations.of(context);
    final user = ref.watch(accountProvider);
    final anonymize = ref.watch(anonymizeProvider);
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.space16),
      child: Tooltip(
        message: t.account.title,
        child: InkResponse(
          radius: AppTheme.icon36 / 2 + AppTheme.space4,
          onTap: () => pushAppPage<void>(
            context,
            window: true,
            title: t.account.title,
            builder: (_) => const AccountScreen(),
          ),
          child: AccountAvatar(
            user: user,
            size: AppTheme.icon36,
            anonymize: anonymize,
          ),
        ),
      ),
    );
  }
}

/// The account in a computer's title bar: the same avatar, small enough
/// for the bar, there on every page - a session in front included - and a
/// click away from the account screen. [navigatorContext] is the app's
/// navigator, which the title bar sits above.
class TitleBarAccountButton extends ConsumerWidget {
  const TitleBarAccountButton({super.key, required this.navigatorContext});

  final BuildContext? Function() navigatorContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AccountService.instance.available) return const SizedBox.shrink();
    final t = Translations.of(context);
    final user = ref.watch(accountProvider);
    final anonymize = ref.watch(anonymizeProvider);
    return Tooltip(
      message: t.account.title,
      child: InkResponse(
        key: const ValueKey('titleBarAccount'),
        radius: AppTheme.icon16,
        onTap: () {
          final target = navigatorContext();
          if (target == null) return;
          pushAppPage<void>(
            target,
            window: true,
            title: t.account.title,
            builder: (_) => const AccountScreen(),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: AccountAvatar(
            user: user,
            size: AppTheme.icon20,
            anonymize: anonymize,
          ),
        ),
      ),
    );
  }
}

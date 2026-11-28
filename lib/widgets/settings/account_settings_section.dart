import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../screens/settings/account_screen.dart';
import '../../services/account/account_service.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../account/account_avatar.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Account section: who is signed in, with their avatar and plan, or the
/// way in. Absent from a build that cannot have accounts, so a fork shows
/// nothing it cannot do.
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AccountService.instance.available) return const SizedBox.shrink();
    final t = Translations.of(context);
    final user = ref.watch(accountProvider);
    final anonymize = ref.watch(anonymizeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.account.section),
        const SizedBox(height: AppTheme.space10),
        AppCard.fields(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: ProService.instance.active,
              builder: (context, pro, _) => SettingsTile(
                leading: AccountAvatar(
                  user: user,
                  size: AppTheme.icon40,
                  anonymize: anonymize,
                ),
                title: user == null
                    ? t.account.signIn
                    : anonymize
                    ? '•••'
                    : (user.email ?? user.displayName ?? user.uid),
                subtitle: user == null
                    ? t.account.signInSubtitle
                    : (pro ? t.account.planPro : t.account.planFree),
                destination: () => const AccountScreen(),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space20),
      ],
    );
  }
}

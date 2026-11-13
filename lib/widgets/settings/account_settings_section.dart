import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../screens/settings/account_screen.dart';
import '../../services/account/account_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Account section: who is signed in, or the way in. Absent from a build
/// that cannot have accounts, so a fork shows nothing it cannot do.
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
        AppCard(
          child: SettingsTile(
            icon: PhosphorIconsFill.user,
            title: user == null
                ? t.account.signIn
                : t.account.signedInAs(
                    name: anonymize ? '•••' : (user.email ?? user.uid),
                  ),
            subtitle: user == null ? t.account.signInSubtitle : null,
            destination: () => const AccountScreen(),
          ),
        ),
        const SizedBox(height: AppTheme.space20),
      ],
    );
  }
}

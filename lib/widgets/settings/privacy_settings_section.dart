import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Privacy section: whether a machine name, host or username is shown as-is
/// or anonymized.
class PrivacySettingsSection extends ConsumerWidget {
  const PrivacySettingsSection({super.key});

  Future<void> _onAnonymizeToggle(WidgetRef ref, bool enabled) async {
    await ref.read(anonymizeProvider.notifier).setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.privacy),
        const SizedBox(height: AppTheme.space10),
        AppCard(
          child: SettingsSwitchTile(
            title: t.settings.anonymize,
            subtitle: t.settings.anonymizeSubtitle,
            value: ref.watch(anonymizeProvider),
            onChanged: (enabled) => _onAnonymizeToggle(ref, enabled),
          ),
        ),
      ],
    );
  }
}

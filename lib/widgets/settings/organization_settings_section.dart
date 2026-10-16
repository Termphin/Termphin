import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../screens/groups/groups_screen.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Organization section: the row into groups.
class OrganizationSettingsSection extends StatelessWidget {
  const OrganizationSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.organization),
        const SizedBox(height: AppTheme.space10),
        AppCard(
          child: SettingsTile(
            title: t.groups.title,
            subtitle: t.settings.groupsSubtitle,
            destination: () => const GroupsScreen(),
          ),
        ),
      ],
    );
  }
}

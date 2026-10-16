import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../screens/backup/export_screen.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Data & backup section: the row into export/import.
class DataBackupSettingsSection extends StatelessWidget {
  const DataBackupSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.dataBackup),
        const SizedBox(height: AppTheme.space10),
        AppCard(
          child: SettingsTile(
            title: t.exportScreen.title,
            subtitle: t.settings.exportImportSubtitle,
            destination: () => const ExportScreen(),
          ),
        ),
      ],
    );
  }
}

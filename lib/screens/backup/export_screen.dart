import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/backup/export_service.dart';
import '../../theme/theme.dart';
import '../../widgets/backup/backup_import_options.dart' show formatBackupDate;
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/settings_tile.dart';
import 'backup_export_screen.dart';
import 'backup_import_screen.dart';

/// The fork between the two halves of backup and restore.
///
/// They used to be one screen with both stacked on it, which put a set of
/// export switches in front of someone who came here to restore, and buried
/// the import button under all of them.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.export));
    unawaited(lastBackupAtSetting.load());
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.exportScreen.title)),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space16,
              AppTheme.space20,
              AppTheme.space32,
            ).add(gutter),
            children: [
              AppCard.fields(
                children: [
                  SettingsTile(
                    icon: PhosphorIconsFill.shareNetwork,
                    iconColor: context.colors.textPrimary,
                    title: t.exportScreen.exportSection,
                    subtitle: t.exportScreen.hubExportSubtitle,
                    destination: () => const BackupExportScreen(),
                  ),
                  const AppDivider(indent: AppTheme.space48),
                  SettingsTile(
                    icon: PhosphorIconsFill.folderOpen,
                    iconColor: context.colors.textPrimary,
                    title: t.exportScreen.importSection,
                    subtitle: t.exportScreen.hubImportSubtitle,
                    destination: () => const BackupImportScreen(),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space12),
              ValueListenableBuilder<String>(
                valueListenable: lastBackupAtSetting,
                builder: (context, stored, _) {
                  final at = DateTime.tryParse(stored);
                  return Text(
                    at == null
                        ? t.exportScreen.lastBackupNever
                        : t.exportScreen.lastBackup(date: formatBackupDate(at)),
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

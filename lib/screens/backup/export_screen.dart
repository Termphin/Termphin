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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32).add(gutter),
            children: [
              AppCard.fields(
                children: [
                  _BackupRow(
                    icon: PhosphorIconsFill.shareNetwork,
                    title: t.exportScreen.exportSection,
                    subtitle: t.exportScreen.hubExportSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const BackupExportScreen(),
                      ),
                    ),
                  ),
                  const AppDivider(indent: 50),
                  _BackupRow(
                    icon: PhosphorIconsFill.folderOpen,
                    title: t.exportScreen.importSection,
                    subtitle: t.exportScreen.hubImportSubtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const BackupImportScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: lastBackupAtSetting,
                builder: (context, stored, _) {
                  final at = DateTime.tryParse(stored);
                  return Text(
                    at == null
                        ? t.exportScreen.lastBackupNever
                        : t.exportScreen.lastBackup(date: formatBackupDate(at)),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textTertiary,
                    ),
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

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: Icon(icon, size: 22, color: context.colors.textPrimary),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
      ),
      trailing: Icon(
        PhosphorIconsFill.caretRight,
        size: 18,
        color: context.colors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

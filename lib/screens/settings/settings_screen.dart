import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../widgets/settings/about_settings_section.dart';
import '../../widgets/settings/analytics_settings_section.dart';
import '../../widgets/settings/appearance_settings_section.dart';
import '../../widgets/settings/connection_settings_section.dart';
import '../../widgets/settings/data_backup_settings_section.dart';
import '../../widgets/settings/feedback_settings_section.dart';
import '../../widgets/settings/open_source_settings_section.dart';
import '../../widgets/settings/organization_settings_section.dart';
import '../../widgets/settings/privacy_settings_section.dart';
import '../../widgets/settings/security_settings_section.dart';
import '../../widgets/settings/sftp_settings_section.dart';
import '../../widgets/settings/terminal_controls_settings_section.dart';
import '../../widgets/settings/terminal_settings_section.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// Settings: one widget per section below the large title, each owning its
/// own state. The only thing this screen loads itself is the package info
/// every section's "About" entry and the "New" badges need.
///
/// The body is a plain [Column] in a [SingleChildScrollView] rather than a
/// [ListView]: every section's own async load has to start the moment the
/// screen mounts, not whenever a lazily-built sliver scrolls it into view.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String? _version;

  /// Bare "1.9.0", for [NewBadge]; [_version] carries the build number.
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = '${packageInfo.version} (${packageInfo.buildNumber})';
      _appVersion = packageInfo.version;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return LargeTitleScaffold(
      title: t.settings.title,
      bodyBuilder: (context, scrollController, gutter) => _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space16,
                0,
                AppTheme.space16,
                AppTheme.space32,
              ).add(gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LargeTitleHeader(
                    title: t.settings.title,
                    subtitle: t.settings.subtitle,
                    padding: const EdgeInsets.only(
                      top: AppTheme.space24,
                      bottom: AppTheme.space8,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space16),
                  const AppearanceSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const OrganizationSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const TerminalSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  TerminalControlsSettingsSection(appVersion: _appVersion),
                  const SizedBox(height: AppTheme.space20),
                  const SftpSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const ConnectionSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const SecuritySettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const DataBackupSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const PrivacySettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const FeedbackSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const OpenSourceSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  const AnalyticsSettingsSection(),
                  const SizedBox(height: AppTheme.space20),
                  AboutSettingsSection(version: _version),
                ],
              ),
            ),
    );
  }
}

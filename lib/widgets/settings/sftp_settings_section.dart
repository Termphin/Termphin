import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/editor_settings_screen.dart';
import '../../services/settings/editor_settings.dart';
import '../../services/settings/sftp_settings.dart';
import '../../services/settings/terminal_settings.dart';
import '../../services/sftp/download_location.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_notifications.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// SFTP section: download folder, hidden files, follow-the-terminal and the
/// text editor settings.
class SftpSettingsSection extends StatefulWidget {
  const SftpSettingsSection({super.key});

  @override
  State<SftpSettingsSection> createState() => _SftpSettingsSectionState();
}

class _SftpSettingsSectionState extends State<SftpSettingsSection> {
  bool _loaded = false;
  DownloadFolder? _downloadFolder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final downloadFolder = await DownloadLocation.instance.current();
    if (!mounted) return;
    setState(() {
      _downloadFolder = downloadFolder;
      _loaded = true;
    });
  }

  Future<void> _onPickDownloadFolder() async {
    final t = Translations.of(context);
    try {
      final folder = await DownloadLocation.instance.pick();
      if (folder == null || !mounted) return;
      setState(() => _downloadFolder = folder);
    } on PlatformException {
      if (mounted) {
        AppNotifications.error(context, t.settings.downloadFolderUnavailable);
      }
    }
  }

  Future<void> _onResetDownloadFolder() async {
    await DownloadLocation.instance.clear();
    if (!mounted) return;
    setState(() => _downloadFolder = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.sftp),
        const SizedBox(height: AppTheme.space10),
        AppCard.fields(
          children: [
            SettingsTile(
              title: t.settings.downloadFolder,
              subtitle: isIOSPlatform
                  ? t.settings.downloadFolderIos
                  : (_downloadFolder?.label.isNotEmpty ?? false
                        ? _downloadFolder!.label
                        : t.settings.downloadFolderDefault),
              trailing: isIOSPlatform
                  ? SettingsTileTrailing.none
                  : SettingsTileTrailing.chevron,
              onTap: isIOSPlatform ? null : _onPickDownloadFolder,
            ),
            if (!isIOSPlatform && _downloadFolder != null) ...[
              const AppDivider(),
              SettingsTile(
                title: t.settings.downloadFolderReset,
                trailing: SettingsTileTrailing.none,
                onTap: _onResetDownloadFolder,
              ),
            ],
            const AppDivider(),
            ValueListenableBuilder<bool>(
              valueListenable: sftpShowHiddenSetting,
              builder: (context, showHidden, _) => SettingsSwitchTile(
                title: t.settings.sftpShowHidden,
                subtitle: t.settings.sftpShowHiddenSubtitle,
                value: showHidden,
                onChanged: sftpShowHiddenSetting.set,
              ),
            ),
            const AppDivider(),
            ValueListenableBuilder<bool>(
              valueListenable: sftpFollowTerminalSetting,
              builder: (context, follow, _) => SettingsSwitchTile(
                title: t.settings.sftpFollowTerminal,
                subtitle: t.settings.sftpFollowTerminalSubtitle,
                value: follow,
                onChanged: sftpFollowTerminalSetting.set,
              ),
            ),
            const AppDivider(),
            SettingsTile(
              title: t.settings.textEditor,
              subtitle: t.settings.textEditorSubtitle(
                font:
                    kTerminalFontLabels[editorSettings.fontFamily.value] ?? '',
                size: editorSettings.fontSize.value.toStringAsFixed(1),
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const EditorSettingsScreen(),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }
}

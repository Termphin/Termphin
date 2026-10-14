import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/fast_upload_settings_screen.dart';
import '../../screens/settings/terminal_appearance_screen.dart';
import '../../services/settings/upload_settings.dart';
import '../onboarding/whats_new_modal.dart';
import '../ui/app_card.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Terminal section: the appearance editor and the fast-upload destination.
class TerminalSettingsSection extends StatelessWidget {
  const TerminalSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.terminal),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              SettingsTile(
                title: t.settings.terminalAppearance,
                subtitle: t.settings.terminalNavSubtitle,
                destination: () => const TerminalAppearanceScreen(),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<UploadDestination>(
                valueListenable: uploadDestinationSetting,
                builder: (context, uploadDestination, _) => SettingsTile(
                  title: t.settings.fastUpload,
                  titleTrailing: const FeatureInfoButton(
                    key: ValueKey('fastUploadInfo'),
                    explainerId: kFastUploadExplainerId,
                  ),
                  subtitle: switch (uploadDestination) {
                    UploadDestination.tmp =>
                      t.settings.fastUploadNavSubtitleTmp,
                    UploadDestination.currentDirectory =>
                      t.settings.fastUploadNavSubtitleCurrentDir,
                    UploadDestination.ask =>
                      t.settings.fastUploadNavSubtitleAsk,
                  },
                  destination: () => const FastUploadSettingsScreen(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

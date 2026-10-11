import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/project_urls.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Open source section: the repository to star, the issue tracker, how to
/// contribute and the licence Termphin itself is under.
///
/// The licences of the packages Termphin is built on stay in About, next to
/// the other legal rows.
class OpenSourceSettingsSection extends StatelessWidget {
  const OpenSourceSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    void open(String url) => openExternalUrl(context, Uri.parse(url));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.openSource),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              SettingsTile(
                icon: PhosphorIconsRegular.star,
                iconColor: context.colors.warning,
                title: t.settings.starOnGitHub,
                subtitle: t.settings.starOnGitHubSubtitle,
                trailing: SettingsTileTrailing.external,
                onTap: () => open(ProjectUrls.repository),
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsRegular.githubLogo,
                title: t.settings.issueTracker,
                subtitle: t.settings.issueTrackerSubtitle,
                trailing: SettingsTileTrailing.external,
                onTap: () => open(ProjectUrls.issues),
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsRegular.gitPullRequest,
                iconColor: context.colors.primary,
                title: t.settings.contribute,
                subtitle: t.settings.contributeSubtitle,
                trailing: SettingsTileTrailing.external,
                onTap: () => open(ProjectUrls.contributing),
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsRegular.certificate,
                title: t.settings.sourceLicense,
                subtitle: t.settings.sourceLicenseSubtitle,
                trailing: SettingsTileTrailing.external,
                onTap: () => open(ProjectUrls.license),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

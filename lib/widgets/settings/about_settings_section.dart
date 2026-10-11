import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/release_notes_screen.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/legal_urls.dart';
import '../../services/app/review_prompt_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ui/app_card.dart';
import '../ui/app_notifications.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/section_header.dart';
import '../ui/section_navigator.dart';
import '../ui/settings_tile.dart';

/// About section: version, release notes, rating the app, licenses and the
/// legal documents.
class AboutSettingsSection extends StatelessWidget {
  const AboutSettingsSection({super.key, required this.version});

  /// "1.4.2 (57)", or `null` while [PackageInfo] is still loading.
  final String? version;

  /// Flutter collects these from every package that ships a LICENSE file,
  /// so the list stays right on its own as dependencies come and go.
  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Termphin',
      applicationVersion: version,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          PhosphorIconsFill.terminalWindow,
          size: 40,
          color: context.colors.primary,
        ),
      ),
    );
  }

  void _showReleaseNotes(BuildContext context) {
    pushAppPage<void>(
      context,
      window: true,
      title: Translations.of(context).settings.releaseNotes,
      builder: (_) => const ReleaseNotesScreen(),
    );
  }

  /// Straight to the store listing, not Play's in-app dialog - that one is
  /// quota'd and silently does nothing most of the time, which is wrong for a
  /// row the user deliberately tapped.
  Future<void> _rateApp(BuildContext context) async {
    unawaited(
      AnalyticsService.instance.capture(AnalyticsEvent.reviewStoreOpened),
    );
    final t = Translations.of(context);
    try {
      await ReviewPromptService.instance.openStoreListing();
    } catch (_) {
      if (context.mounted) {
        AppNotifications.error(
          context,
          isIOSPlatform
              ? t.settings.rateAppFailedIos
              : t.settings.rateAppFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.about),
        const SizedBox(height: 10),
        AppCard(
          clipChild: true,
          child: Column(
            children: [
              SettingsTile(
                icon: PhosphorIconsFill.terminalWindow,
                title: 'Termphin',
                subtitle: version == null
                    ? t.settings.aboutTagline
                    : t.settings.aboutVersion(version: version!),
                trailing: SettingsTileTrailing.none,
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsFill.sparkle,
                title: t.settings.releaseNotes,
                subtitle: t.settings.releaseNotesSubtitle,
                onTap: () => _showReleaseNotes(context),
              ),
              if (ReviewPromptService.instance.canOpenStoreListing) ...[
                const Divider(height: 1),
                SettingsTile(
                  icon: PhosphorIconsFill.star,
                  title: t.settings.rateApp,
                  subtitle: isIOSPlatform
                      ? t.settings.rateAppSubtitleIos
                      : t.settings.rateAppSubtitle,
                  trailing: SettingsTileTrailing.external,
                  onTap: () => _rateApp(context),
                ),
              ],
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsFill.scales,
                title: t.settings.licenses,
                subtitle: t.settings.licensesSubtitle,
                onTap: () => _showLicenses(context),
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsFill.shieldCheck,
                title: t.settings.privacyPolicy,
                subtitle: t.settings.privacyPolicySubtitle,
                trailing: SettingsTileTrailing.external,
                onTap: () => openExternalUrl(
                  context,
                  Uri.parse(LegalUrls.privacyPolicy),
                ),
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsFill.fileText,
                title: t.settings.terms,
                subtitle: t.settings.termsSubtitle,
                trailing: SettingsTileTrailing.external,
                onTap: () => openExternalUrl(
                  context,
                  Uri.parse(LegalUrls.termsOfService),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/error_reports_screen.dart';
import '../../screens/settings/manual_screen.dart';
import '../ui/app_card.dart';
import '../ui/clipboard_and_links.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Feedback section: email, the error reports to send with a bug, and the
/// manual. The issue tracker sits in the open source section.
class FeedbackSettingsSection extends StatelessWidget {
  const FeedbackSettingsSection({super.key});

  /// Opens the device's mail app with the address and subject already
  /// filled in - no in-app form, no backend to receive it.
  Future<void> _sendFeedback(
    BuildContext context, {
    required bool isBug,
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'contact@termphin.dev',
      queryParameters: {
        'subject': isBug ? 'Termphin bug report' : 'Termphin feedback',
      },
    );
    await openExternalUrl(
      context,
      uri,
      failureMessage: t.settings.feedbackEmailFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.feedback),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              SettingsTile(
                title: t.settings.sendFeedback,
                subtitle: t.settings.sendFeedbackSubtitle,
                onTap: () => _sendFeedback(context, isBug: false),
              ),
              const Divider(height: 1),
              SettingsTile(
                title: t.settings.reportBug,
                subtitle: t.settings.reportBugSubtitle,
                onTap: () => _sendFeedback(context, isBug: true),
              ),
              const Divider(height: 1),
              SettingsTile(
                title: t.settings.errorReports,
                subtitle: t.settings.errorReportsSubtitle,
                destination: () => const ErrorReportsScreen(),
              ),
              const Divider(height: 1),
              SettingsTile(
                title: t.settings.manual,
                subtitle: t.settings.manualSubtitle,
                destination: () => const ManualScreen(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/app/manual_urls.dart';
import '../../theme/theme.dart';
import '../settings/manual_link.dart';
import '../ui/app_sheet.dart';
import '../ui/clipboard_and_links.dart';

const _agentRepoUrl = 'https://github.com/Termphin/termphin-agent';

/// Explains the remote agent and links to its source - shared by Settings
/// and onboarding, so both point at the exact same explanation.
Future<void> showRemoteAgentInfoSheet(BuildContext context) {
  final t = Translations.of(context);
  return showAppSheet<void>(
    context: context,
    builder: (ctx) => RemoteAgentInfoSheet(t: t),
  );
}

class RemoteAgentInfoSheet extends StatelessWidget {
  const RemoteAgentInfoSheet({super.key, required this.t});

  final Translations t;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space20,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.settings.agentSheetTitle, style: textTheme.titleLarge),
            const SizedBox(height: AppTheme.space12),
            Text(
              t.settings.agentSheetIntro,
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.space20),
            _AgentPoint(
              icon: PhosphorIconsRegular.desktopTower,
              text: t.settings.agentSheetPointPlatforms,
            ),
            _AgentPoint(
              icon: PhosphorIconsRegular.plugsConnected,
              text: t.settings.agentSheetPointKeepsAlive,
            ),
            _AgentPoint(
              icon: PhosphorIconsRegular.wifiSlash,
              text: t.settings.agentSheetPointNoNetwork,
            ),
            _AgentPoint(
              icon: PhosphorIconsRegular.userCircle,
              text: t.settings.agentSheetPointNoRoot,
            ),
            _AgentPoint(
              icon: PhosphorIconsRegular.folderSimple,
              text: t.settings.agentSheetPointFiles,
            ),
            _AgentPoint(
              icon: PhosphorIconsRegular.brain,
              text: t.settings.agentSheetPointMemory,
            ),
            _AgentPoint(
              icon: PhosphorIconsRegular.fingerprint,
              text: t.settings.agentSheetPointVerified,
            ),
            const SizedBox(height: AppTheme.space8),
            Text(
              t.settings.agentSheetOpenSource,
              style: textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openRepo(context),
                icon: const Icon(
                  PhosphorIconsRegular.githubLogo,
                  size: AppTheme.icon18,
                ),
                label: Text(t.settings.agentSheetRepoButton),
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => openManual(context, ManualPage.remoteAgent),
                child: Text(t.manual.readMore),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRepo(BuildContext context) => openExternalUrl(
    context,
    Uri.parse(_agentRepoUrl),
    failureMessage: t.settings.agentSheetLinkFailed,
  );
}

class _AgentPoint extends StatelessWidget {
  const _AgentPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.icon18, color: context.colors.primary),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

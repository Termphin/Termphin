import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/error_reports_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../services/app/error_reports.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// The errors [ErrorReports] kept, opened from Settings, with ways to send
/// them: by email to the address the bug report tile uses, or through the
/// share sheet for anywhere else (a GitHub issue, a chat).
///
/// With Anonymize on, the hosts and usernames of every saved machine are
/// scrubbed both on screen and in what is sent, since an error message is
/// free text that can carry either.
class ErrorReportsScreen extends ConsumerWidget {
  const ErrorReportsScreen({super.key});

  /// A mail app is handed the body in a URI, which some refuse past a few
  /// kilobytes; the share sheet carries the full text.
  static const _maxEmailBody = 6000;

  static String _scrub(String text, List<SshProfile>? profiles) {
    if (profiles == null) return text;
    for (final profile in profiles) {
      text = anonymizeConnectionLog([text], profile).single;
    }
    return text;
  }

  static Future<String> _exportText(
    ErrorReports reports,
    List<SshProfile>? scrubFor,
  ) async {
    final info = await PackageInfo.fromPlatform();
    final header =
        'Termphin ${info.version} (${info.buildNumber}), '
        '${defaultTargetPlatform.name}';
    return _scrub(reports.export(header: header), scrubFor);
  }

  Future<void> _sendEmail(
    BuildContext context,
    ErrorReports reports,
    List<SshProfile>? scrubFor,
  ) async {
    final text = await _exportText(reports, scrubFor);
    if (!context.mounted) return;
    final body = text.length > _maxEmailBody
        ? text.substring(0, _maxEmailBody)
        : text;
    await openExternalUrl(
      context,
      Uri(
        scheme: 'mailto',
        path: 'contact@termphin.dev',
        queryParameters: {'subject': t.errorReports.emailSubject, 'body': body},
      ),
      failureMessage: t.settings.feedbackEmailFailed,
    );
  }

  Future<void> _share(
    BuildContext context,
    ErrorReports reports,
    List<SshProfile>? scrubFor,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? (box.localToGlobal(Offset.zero) & box.size)
        : null;
    final text = await _exportText(reports, scrubFor);
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }

  Future<void> _clear(BuildContext context, ErrorReports reports) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.errorReports.clearTitle,
      message: t.errorReports.clearMessage,
      confirmLabel: t.errorReports.clear,
      destructive: true,
    );
    if (confirmed) await reports.clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final reports = ref.watch(errorReportsProvider);
    final scrubFor = ref.watch(anonymizeProvider)
        ? ref.watch(profilesProvider)
        : null;
    return ListenableBuilder(
      listenable: reports,
      builder: (context, _) {
        final items = reports.reports;
        final empty = items.isEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.settings.errorReports),
            actions: [
              IconButton(
                tooltip: t.errorReports.sendEmail,
                icon: const Icon(PhosphorIconsRegular.envelopeSimple),
                onPressed: empty
                    ? null
                    : () => _sendEmail(context, reports, scrubFor),
              ),
              IconButton(
                tooltip: t.errorReports.share,
                icon: const Icon(PhosphorIconsRegular.shareNetwork),
                onPressed: empty
                    ? null
                    : () => _share(context, reports, scrubFor),
              ),
              IconButton(
                tooltip: t.errorReports.clear,
                icon: const Icon(PhosphorIconsRegular.trash),
                onPressed: empty ? null : () => _clear(context, reports),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: empty
                ? EmptyStatePanel(
                    icon: PhosphorIconsRegular.checkCircle,
                    title: t.errorReports.empty,
                    subtitle: t.errorReports.emptySubtitle,
                  )
                : ContentGutter(
                    builder: (context, gutter) => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        32,
                      ).add(gutter),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => index == 0
                          ? Text(
                              t.errorReports.privacy,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.colors.textTertiary,
                                  ),
                            )
                          : _ReportCard(
                              report: items[index - 1],
                              scrub: (text) => _scrub(text, scrubFor),
                            ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.scrub});

  final ErrorReport report;
  final String Function(String) scrub;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final time = report.time.toLocal().toString().substring(0, 19);
    final repeated = report.count > 1
        ? ' · ${t.errorReports.repeated(count: report.count)}'
        : '';
    final mono = context.colors.monoStyle.copyWith(
      fontSize: 12,
      color: context.colors.textSecondary,
      height: 1.5,
    );
    return AppCard(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          scrub(report.message),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Text(
          '$time$repeated',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SizedBox(
            width: double.infinity,
            child: SelectableText(
              scrub('${report.message}\n\n${report.stack}'),
              style: mono,
            ),
          ),
        ],
      ),
    );
  }
}

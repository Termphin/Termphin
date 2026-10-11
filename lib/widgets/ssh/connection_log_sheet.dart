import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/ssh_connection_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/app/manual_urls.dart';
import '../../theme/theme.dart';
import '../ui/app_sheet.dart';
import '../ui/manual_link.dart';

/// The connection log for a session, readable after the tab is past the
/// connecting screen. Live, since the log keeps growing for as long as the
/// shell's stderr stays open - a server writing an out-of-band message after
/// the terminal is already up.
Future<void> showConnectionLogSheet(
  BuildContext context,
  (String, SshProfile) session,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  if (!context.mounted) return;
  await showAppSheet<void>(
    context: context,
    builder: (sheetContext) {
      final t = Translations.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.connection.viewLog,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final rawLog = ref
                      .watch(sshConnectionProvider(session))
                      .connectionLog;
                  final anonymize = ref.watch(anonymizeProvider);
                  final log = anonymize
                      ? anonymizeConnectionLog(rawLog, session.$2)
                      : rawLog;
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          log.isEmpty ? t.connection.logEmpty : log.join('\n'),
                          style: context.colors.monoStyle.copyWith(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    openManual(sheetContext, ManualPage.troubleshooting),
                icon: const Icon(PhosphorIconsRegular.question, size: 18),
                label: Text(t.manual.troubleshooting),
              ),
            ],
          ),
        ),
      );
    },
  );
}

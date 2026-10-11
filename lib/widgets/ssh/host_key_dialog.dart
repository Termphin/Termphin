import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app.dart';
import '../../i18n/strings.g.dart';
import '../../models/known_host.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/app/manual_urls.dart';
import '../../services/ssh/ssh_prompts.dart';
import '../../theme/theme.dart';
import '../ui/manual_link.dart';

/// Asks about a host key from outside any widget's context.
///
/// The question is raised by `SshService` mid-handshake, which has no context
/// of its own, so this reaches for the root navigator the same way the rest
/// of the app's context-less UI does. No navigator means no way to ask, and
/// an unanswerable question is a no: the caller reads false as "do not
/// connect", which is the safe end of the guess. Not dismissible by a stray
/// tap outside: a key that is not the pinned one is exactly the moment
/// nothing should be decided by accident.
Future<bool> showHostKeyPrompt(HostKeyPromptRequest request) async {
  final context = navigatorKey.currentContext;
  if (context == null) return false;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _HostKeyDialog(request: request),
  );
  return accepted ?? false;
}

class _HostKeyDialog extends ConsumerWidget {
  const _HostKeyDialog({required this.request});

  final HostKeyPromptRequest request;

  bool get _changed => request.verdict == HostKeyVerdict.changed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final accent = _changed ? colors.error : colors.primary;
    final anonymize = ref.watch(anonymizeProvider);
    final displayHost = anonymize
        ? IdentityAnonymizer.host(request.host)
        : request.host;

    return AlertDialog(
      icon: Icon(
        _changed
            ? PhosphorIconsFill.warningOctagon
            : PhosphorIconsRegular.shieldCheck,
        color: accent,
        size: 28,
      ),
      title: Text(_changed ? t.hostKey.changedTitle : t.hostKey.newTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.hostKey.endpoint(host: displayHost, port: '${request.port}'),
              style: colors.itemTitle,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              _changed ? t.hostKey.changedBody : t.hostKey.newBody,
              style: colors.uiStyle,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            _Fingerprint(
              label: t.hostKey.fingerprintLabel,
              value: request.fingerprint,
              accent: accent,
            ),
            if (_changed && request.pinnedFingerprint != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              _Fingerprint(
                label: t.hostKey.pinnedLabel,
                value: request.pinnedFingerprint!,
                accent: colors.textTertiary,
              ),
            ],
            const SizedBox(height: AppTheme.spaceMd),
            Text(
              '${t.hostKey.keyTypeLabel}: ${request.keyType}',
              style: colors.uiSmall,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(t.hostKey.verifyHint, style: colors.uiSmall),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => openManual(context, ManualPage.hostKeys),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(t.manual.whatIsThis),
              ),
            ),
            if (_changed) ...[
              const SizedBox(height: AppTheme.spaceLg),
              Text(
                t.hostKey.changedWarning,
                style: colors.uiStyle.copyWith(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.hostKey.reject),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: accent),
          child: Text(_changed ? t.hostKey.acceptChanged : t.hostKey.accept),
        ),
      ],
    );
  }
}

/// Monospace and wrapped rather than ellipsised - a fingerprint is only
/// useful if every character of it is on screen to compare.
class _Fingerprint extends StatelessWidget {
  const _Fingerprint({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: colors.surfaceOffset,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: colors.uiSmall.copyWith(color: accent)),
          const SizedBox(height: AppTheme.spaceXs),
          SelectableText(
            value,
            style: colors.monoStyle.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

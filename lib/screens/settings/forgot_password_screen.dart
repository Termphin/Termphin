import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/account/account_service.dart';
import '../../theme/theme.dart';
import '../../widgets/account/account_failure_text.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// Setting a new password by email: one field for the address, already
/// holding what was typed on the sign-in form, and once the link is sent a
/// screen that says where to look and offers to send it again.
///
/// It never says whether an account uses the address - the reply is the
/// same either way, which keeps the screen from telling anyone whose
/// address is registered.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  final String email;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = Translations.of(context);
    final email = _email.text.trim();
    setState(() => _busy = true);
    try {
      await AccountService.instance.sendPasswordReset(email);
      if (mounted) setState(() => _sentTo = email);
    } on AccountException catch (error) {
      if (mounted) {
        AppNotifications.error(context, accountFailureText(t, error.failure));
      }
    } catch (_) {
      if (mounted) {
        AppNotifications.error(
          context,
          accountFailureText(t, AccountFailure.unknown),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = Translations.of(context).account.reset;
    final text = Theme.of(context).textTheme;
    final anonymize = ref.watch(anonymizeProvider);
    final sentTo = _sentTo;
    return LargeTitleScaffold(
      title: r.title,
      bodyBuilder: (context, scrollController, gutter) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space16,
          0,
          AppTheme.space16,
          AppTheme.space32,
        ).add(gutter),
        children: [
          LargeTitleHeader(
            title: sentTo == null ? r.title : r.sentTitle,
            padding: const EdgeInsets.only(
              top: AppTheme.space24,
              bottom: AppTheme.space8,
            ),
          ),
          if (sentTo == null) ...[
            Text(r.body, style: text.bodyMedium),
            const SizedBox(height: AppTheme.space20),
            AppFormField(
              controller: _email,
              label: Translations.of(context).account.email,
              icon: PhosphorIconsRegular.envelopeSimple,
              keyboardType: TextInputType.emailAddress,
              action: TextInputAction.send,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) {
                if (!_busy) unawaited(_send());
              },
            ),
            const SizedBox(height: AppTheme.space16),
            FilledButton(onPressed: _busy ? null : _send, child: Text(r.send)),
          ] else ...[
            Icon(
              PhosphorIconsRegular.envelopeOpen,
              size: AppTheme.icon48,
              color: context.colors.primary,
            ),
            const SizedBox(height: AppTheme.space16),
            Text(
              r.sentBody(email: anonymize ? '•••' : sentTo),
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppTheme.space24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(r.back),
            ),
            const SizedBox(height: AppTheme.space8),
            TextButton(onPressed: _busy ? null : _send, child: Text(r.resend)),
          ],
        ],
      ),
    );
  }
}

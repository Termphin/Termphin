import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/forgot_password_screen.dart';
import '../../services/account/account_service.dart';
import '../../theme/theme.dart';
import '../ui/app_form_field.dart';
import '../ui/app_notifications.dart';
import '../ui/legal_links.dart';
import 'account_failure_text.dart';
import 'sign_in_buttons.dart';

/// The ways to sign in - Google, Apple where the backend offers it, or an
/// email and password - with the link to reset a forgotten password. Shows
/// nothing about who is signed in: the caller watches the account and decides
/// what to do once someone is.
class SignInPanel extends StatefulWidget {
  const SignInPanel({super.key});

  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<SignInPanel> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _supportsApple = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProviders());
  }

  Future<void> _loadProviders() async {
    final supportsApple = await AccountService.instance.supportsApple;
    if (mounted) setState(() => _supportsApple = supportsApple);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Runs [action] with the buttons held, and says what went wrong in the
  /// panel's own words. A cancelled sheet is not an error. Success closes
  /// the autofill context, which is a password manager's cue to offer to
  /// save what was typed.
  Future<bool> _attempt(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      TextInput.finishAutofillContext();
      return true;
    } on AccountException catch (error) {
      if (mounted && error.failure != AccountFailure.cancelled) {
        AppNotifications.error(context, _failureText(error.failure));
      }
      return false;
    } catch (_) {
      if (mounted) {
        AppNotifications.error(context, _failureText(AccountFailure.unknown));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failureText(AccountFailure failure) =>
      accountFailureText(Translations.of(context), failure);

  Future<void> _resetPassword() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ForgotPasswordScreen(email: _email.text.trim()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoogleSignInButton(
          label: t.account.continueWithGoogle,
          onPressed: _busy
              ? null
              : () => _attempt(AccountService.instance.signInWithGoogle),
        ),
        const SizedBox(height: AppTheme.space10),
        GitHubSignInButton(
          label: t.account.continueWithGitHub,
          onPressed: _busy
              ? null
              : () => _attempt(AccountService.instance.signInWithGitHub),
        ),
        if (_supportsApple) ...[
          const SizedBox(height: AppTheme.space10),
          AppleSignInButton(
            label: t.account.continueWithApple,
            onPressed: _busy
                ? null
                : () => _attempt(AccountService.instance.signInWithApple),
          ),
        ],
        const SizedBox(height: AppTheme.space24),
        Text(
          t.account.orEmail,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: AppTheme.space10),
        AutofillGroup(
          child: Column(
            children: [
              AppFormField(
                controller: _email,
                label: t.account.email,
                icon: PhosphorIconsRegular.envelopeSimple,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: AppTheme.space10),
              AppFormField(
                controller: _password,
                label: t.account.password,
                icon: PhosphorIconsRegular.lockKey,
                obscure: true,
                action: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.space14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _attempt(
                        () => AccountService.instance.createWithEmail(
                          _email.text,
                          _password.text,
                        ),
                      ),
                child: Text(t.account.createAccount),
              ),
            ),
            const SizedBox(width: AppTheme.space10),
            Expanded(
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _attempt(
                        () => AccountService.instance.signInWithEmail(
                          _email.text,
                          _password.text,
                        ),
                      ),
                child: Text(t.account.signInWithEmail),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : _resetPassword,
            child: Text(t.account.forgotPassword),
          ),
        ),
        const SizedBox(height: AppTheme.space12),
        Text(
          t.account.agreeNotice,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
        ),
        const LegalLinks(),
      ],
    );
  }
}

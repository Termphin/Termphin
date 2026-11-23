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
import '../ui/clipboard_and_links.dart';
import '../ui/legal_links.dart';
import '../ui/section_navigator.dart';
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

  Future<void> _resetPassword() => pushAppPage<void>(
    context,
    window: true,
    title: Translations.of(context).account.reset.title,
    builder: (_) => ForgotPasswordScreen(email: _email.text.trim()),
  );

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    if (AccountService.instance.signsInThroughBrowser) {
      return const BrowserSignInPanel();
    }
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

/// Signing in on a computer, where the providers' own sign-in does not run:
/// one button that opens the account page in the browser and shows the code
/// to confirm there, then waits until it is confirmed, the user cancels, or
/// the code runs out.
class BrowserSignInPanel extends StatefulWidget {
  const BrowserSignInPanel({super.key});

  @override
  State<BrowserSignInPanel> createState() => _BrowserSignInPanelState();
}

class _BrowserSignInPanelState extends State<BrowserSignInPanel> {
  BrowserSignIn? _link;
  bool _busy = false;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _cancelled = false;
      _link = null;
    });
    try {
      await AccountService.instance.signInThroughBrowser((link) {
        if (!mounted) return;
        setState(() => _link = link);
        unawaited(openExternalUrl(context, link.page));
      }, cancelled: () => _cancelled || !mounted);
    } on AccountException catch (error) {
      if (mounted && error.failure != AccountFailure.cancelled) {
        AppNotifications.error(
          context,
          accountFailureText(Translations.of(context), error.failure),
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotifications.error(
          context,
          accountFailureText(Translations.of(context), AccountFailure.unknown),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _link = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final link = _link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.account.browser.intro,
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppTheme.space16),
        if (link == null)
          FilledButton.icon(
            key: const ValueKey('browserSignIn'),
            onPressed: _busy ? null : _start,
            icon: const Icon(PhosphorIconsRegular.globe),
            label: Text(t.account.browser.start),
          )
        else ...[
          Text(
            t.account.browser.code,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppTheme.space6),
          SelectableText(
            link.code,
            key: const ValueKey('browserSignInCode'),
            style: colors.monoStyle.copyWith(
              fontSize: AppTheme.font26,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              const SizedBox.square(
                dimension: AppTheme.icon16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppTheme.space10),
              Expanded(
                child: Text(
                  t.account.browser.waiting,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => unawaited(openExternalUrl(context, link.page)),
                child: Text(t.account.browser.openAgain),
              ),
              const SizedBox(width: AppTheme.space8),
              TextButton(
                onPressed: () => setState(() => _cancelled = true),
                child: Text(t.common.cancel),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppTheme.space16),
        Text(
          t.account.agreeNotice,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
        const LegalLinks(),
      ],
    );
  }
}

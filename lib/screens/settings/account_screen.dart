import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/account/account_service.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../../widgets/account/account_avatar.dart';
import '../../widgets/account/account_failure_text.dart';
import '../../widgets/account/pro_card.dart';
import '../../widgets/account/sign_in_buttons.dart';
import '../../widgets/account/sync_card.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/settings_tile.dart';
import '../../widgets/ui/text_input_dialog.dart';
import 'forgot_password_screen.dart';

/// Signing in, and once signed in, who you are and the ways out: signing out
/// and deleting the account, which the stores require be reachable from the
/// app itself.
///
/// The account is only for Pro, and the screen says so before anything
/// else, so nobody signs in thinking the app needs it.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
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
  /// screen's own words. A cancelled sheet is not an error. Success closes
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

  Future<void> _signOut() async {
    final t = Translations.of(context);
    if (await _attempt(AccountService.instance.signOut) && mounted) {
      unawaited(ProService.instance.signedOut());
      _password.clear();
      AppNotifications.info(context, t.account.signedOut);
    }
  }

  Future<void> _resendVerification(String email) async {
    final t = Translations.of(context);
    final sent = await _attempt(AccountService.instance.sendEmailVerification);
    if (sent && mounted) {
      AppNotifications.info(context, t.account.verifySent(email: email));
    }
  }

  Future<void> _checkVerification() async {
    final t = Translations.of(context);
    if (!await _attempt(AccountService.instance.refresh) || !mounted) return;
    final verified = AccountService.instance.user?.emailVerified ?? false;
    if (verified) {
      AppNotifications.success(context, t.account.verifyDone);
    } else {
      AppNotifications.info(context, t.account.verifyNotYet);
    }
  }

  Future<void> _delete(AccountUser user) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.account.deleteTitle,
      message: t.account.deleteMessage,
      confirmLabel: t.account.deleteConfirm,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    String? password;
    if (user.provider == AccountProvider.password) {
      password = await showTextInputDialog(
        context,
        title: t.account.passwordToDelete,
        confirmLabel: t.account.deleteConfirm,
        obscure: true,
      );
      if (password == null || !mounted) return;
    }
    final deleted = await _attempt(
      () => AccountService.instance.deleteAccount(password: password),
    );
    if (deleted && mounted) {
      _password.clear();
      AppNotifications.info(context, t.account.deleted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final user = ref.watch(accountProvider);
    return LargeTitleScaffold(
      title: t.account.title,
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
            title: t.account.title,
            subtitle: user == null ? t.account.intro : null,
            padding: const EdgeInsets.only(
              top: AppTheme.space24,
              bottom: AppTheme.space8,
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          if (!AccountService.instance.available)
            Text(
              t.account.unavailable,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textTertiary,
              ),
            )
          else if (user == null)
            ..._signInOptions(context)
          else
            ..._signedIn(context, user),
        ],
      ),
    );
  }

  List<Widget> _signInOptions(BuildContext context) {
    final t = Translations.of(context);
    return [
      GoogleSignInButton(
        label: t.account.continueWithGoogle,
        onPressed: _busy
            ? null
            : () => _attempt(AccountService.instance.signInWithGoogle),
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
    ];
  }

  /// Asks a password account to confirm its address, with the two things
  /// to do about it: have the link sent again, or say it has been followed.
  Widget _verificationCard(
    BuildContext context,
    AccountUser user,
    String name,
  ) {
    final t = Translations.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(AppTheme.space14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.account.verifyTitle, style: text.titleMedium),
          const SizedBox(height: AppTheme.space6),
          Text(
            t.account.verifyBody(email: name),
            style: text.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _resendVerification(user.email ?? ''),
                  child: Text(t.account.verifyResend),
                ),
              ),
              const SizedBox(width: AppTheme.space10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _checkVerification,
                  child: Text(t.account.verifyCheck),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _signedIn(BuildContext context, AccountUser user) {
    final t = Translations.of(context);
    final anonymize = ref.watch(anonymizeProvider);
    final name = anonymize
        ? '•••'
        : (user.email ?? user.displayName ?? user.uid);
    final provider = switch (user.provider) {
      AccountProvider.google => t.account.providerGoogle,
      AccountProvider.apple => t.account.providerApple,
      AccountProvider.password => t.account.providerPassword,
    };
    return [
      _identity(context, user, name, provider),
      const SizedBox(height: AppTheme.space20),
      if (!user.emailVerified) ...[
        _verificationCard(context, user, name),
        const SizedBox(height: AppTheme.space16),
        Text(
          t.account.sync.verifyFirst,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.textTertiary),
        ),
      ] else ...[
        const ProCard(),
        const SizedBox(height: AppTheme.space16),
        const SyncCard(),
      ],
      const SizedBox(height: AppTheme.space24),
      AppCard(
        child: Column(
          children: [
            SettingsTile(
              icon: PhosphorIconsRegular.signOut,
              title: t.account.signOut,
              trailing: SettingsTileTrailing.none,
              onTap: _busy ? null : _signOut,
            ),
            SettingsTile(
              icon: PhosphorIconsRegular.trash,
              iconColor: context.colors.error,
              title: t.account.deleteAccount,
              trailing: SettingsTileTrailing.none,
              onTap: _busy ? null : () => _delete(user),
            ),
          ],
        ),
      ),
    ];
  }

  /// Who is signed in, at the top of the screen: the avatar, the address,
  /// how they signed in and whether the account has Pro.
  Widget _identity(
    BuildContext context,
    AccountUser user,
    String name,
    String provider,
  ) {
    final t = Translations.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        AccountAvatar(
          user: user,
          size: AppTheme.icon56,
          anonymize: ref.watch(anonymizeProvider),
        ),
        const SizedBox(width: AppTheme.space14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppTheme.space4),
              Row(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: ProService.instance.active,
                    builder: (context, pro, _) => AppBadge(
                      pro ? t.account.planPro : t.account.planFree,
                      tone: pro ? BadgeTone.accent : BadgeTone.neutral,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Flexible(
                    child: Text(
                      t.account.signedInWith(provider: provider),
                      style: text.bodySmall?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

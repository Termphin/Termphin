import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../i18n/strings.g.dart';
import '../providers/groups_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/snippets_provider.dart';
import '../providers/ssh_keys_provider.dart';
import '../providers/sync_provider.dart';
import '../services/account/account_service.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app/legal_urls.dart';
import '../services/app/onboarding_service.dart';
import '../services/platform/foreground_notification_service.dart';
import '../services/ssh/local_network_permission.dart';
import '../services/sync/sync_engine.dart';
import '../services/sync/sync_service.dart';
import '../theme/theme.dart';
import '../utils/platform_info.dart';
import '../widgets/profiles/server_guide.dart';
import '../widgets/ui/app_card.dart';
import '../widgets/ui/app_divider.dart';
import '../widgets/ui/app_form_field.dart';
import '../widgets/ui/clipboard_and_links.dart';
import '../widgets/ui/permission_tile.dart';
import '../widgets/ui/settings_tile.dart';
import 'settings/account_screen.dart';

/// What onboarding was told about having a server, which decides where the
/// app goes once it closes.
///
/// [synced] is a returning user whose account already syncs and whose
/// machines have just arrived: the machine list is the destination, and the
/// server question was not asked.
enum ServerAnswer { hasServer, notYet, synced }

/// The pages onboarding can show, in the order they come.
enum _Step { welcome, server, unlock, permissions, analytics }

/// How a returning user came in: not at all, to a synced account whose
/// passphrase is still to be entered, or to a synced account already unlocked
/// on this device.
enum _Returning { none, locked, unlocked }

/// First-launch flow: what Termphin is, whether there is a server to connect
/// to, permissions, then analytics consent.
///
/// The server question is the point of it. Most people who installed and never
/// connected had no machine to connect to, and the old flow never asked - it
/// ended on an empty list with a single add button.
///
/// A returning user signs in from the welcome page. If their account already
/// syncs, the server question is replaced by the sync passphrase, or skipped
/// when this device already holds it.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    @visibleForTesting this.accountsAvailable,
    @visibleForTesting this.signIn,
    @visibleForTesting this.syncState,
    @visibleForTesting this.unlock,
  });

  final ValueChanged<ServerAnswer> onComplete;

  /// Stands in for [AccountService.available] in tests.
  final bool? accountsAvailable;

  /// Stands in for pushing the sign-in screen in tests. Completes with whether
  /// someone is signed in afterwards.
  final Future<bool> Function(BuildContext context)? signIn;

  /// Stands in for [SyncService.state] in tests.
  final Future<SyncState> Function()? syncState;

  /// Stands in for [SyncService.unlock] in tests.
  final Future<SyncReport> Function(String passphrase)? unlock;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// The server page is the one question that has to be answered to go on;
/// every other page can be swiped past. The unlock page is passed through only
/// by unlocking it or by saying "not now".
class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _analyticsChecked = true;
  ServerAnswer? _answer;
  bool _signedIn = AccountService.instance.user != null;
  _Returning _returning = _Returning.none;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _accountsAvailable =>
      widget.accountsAvailable ?? AccountService.instance.available;

  List<_Step> get _steps => [
    _Step.welcome,
    if (_returning == _Returning.none) _Step.server,
    if (_returning == _Returning.locked) _Step.unlock,
    _Step.permissions,
    _Step.analytics,
  ];

  Future<void> _finish() async {
    await AnalyticsService.instance.setConsent(_analyticsChecked);
    await OnboardingService.instance.markCompleted();
    widget.onComplete(
      _returning == _Returning.unlocked
          ? ServerAnswer.synced
          : _answer ?? ServerAnswer.notYet,
    );
  }

  Future<void> _signIn() async {
    final signedIn = await (widget.signIn ?? _pushSignIn)(context);
    if (!signedIn || !mounted) return;
    final state = await _readSyncState();
    if (!mounted) return;
    setState(() {
      _signedIn = true;
      _returning = switch (state) {
        SyncState.locked => _Returning.locked,
        SyncState.ready => _Returning.unlocked,
        _ => _Returning.none,
      };
    });
  }

  Future<bool> _pushSignIn(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AccountScreen(closeOnSignIn: true),
      ),
    );
    return AccountService.instance.user != null;
  }

  /// A failed read is treated as no sync, so the normal flow goes on.
  Future<SyncState> _readSyncState() async {
    try {
      return await (widget.syncState ?? SyncService.instance.state)();
    } catch (_) {
      return SyncState.signedOut;
    }
  }

  Widget _pageFor(_Step step) => switch (step) {
    _Step.welcome => _WelcomePage(
      onSignIn: _accountsAvailable && !_signedIn ? _signIn : null,
    ),
    _Step.server => _ServerPage(
      answer: _answer,
      onChanged: (a) => setState(() => _answer = a),
    ),
    _Step.unlock => _UnlockSyncPage(
      unlock: widget.unlock ?? SyncService.instance.unlock,
      onUnlocked: () => setState(() => _returning = _Returning.unlocked),
      onNotNow: () => setState(() => _returning = _Returning.none),
    ),
    _Step.permissions => const _PermissionsPage(),
    _Step.analytics => _AnalyticsPage(
      checked: _analyticsChecked,
      onChanged: (v) => setState(() => _analyticsChecked = v),
    ),
  };

  bool _canContinue(_Step step) => switch (step) {
    _Step.server => _answer != null,
    _Step.unlock => false,
    _ => true,
  };

  void _next() {
    _pageController.nextPage(
      duration: AppTheme.motionSlow,
      curve: AppTheme.interactiveCurve,
    );
  }

  void _back() {
    _pageController.previousPage(
      duration: AppTheme.motionSlow,
      curve: AppTheme.interactiveCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _page = page),
                children: [for (final step in steps) _pageFor(step)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space24,
                AppTheme.space8,
                AppTheme.space24,
                AppTheme.space24,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      steps.length,
                      (index) => AnimatedContainer(
                        duration: AppTheme.motionSlow,
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space4,
                        ),
                        width: index == _page ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: index == _page
                              ? context.colors.primary
                              : context.colors.surfaceBorder,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.space20),
                  _OnboardingActions(
                    page: _page,
                    pageCount: steps.length,
                    canContinue: _canContinue(steps[_page]),
                    onBack: _back,
                    onContinue: _next,
                    onFinish: _finish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingActions extends StatelessWidget {
  const _OnboardingActions({
    required this.page,
    required this.pageCount,
    required this.canContinue,
    required this.onBack,
    required this.onContinue,
    required this.onFinish,
  });

  final int page;
  final int pageCount;
  final bool canContinue;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isLast = page == pageCount - 1;
    return Row(
      children: [
        if (page > 0)
          TextButton(onPressed: onBack, child: Text(t.onboarding.back)),
        const Spacer(),
        FilledButton(
          onPressed: !canContinue ? null : (isLast ? onFinish : onContinue),
          child: Text(switch (page) {
            0 => t.onboarding.getStarted,
            _ when isLast => t.onboarding.finish,
            _ => t.onboarding.continueAction,
          }),
        ),
      ],
    );
  }
}

/// The real logo and one sentence about what the app is for.
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onSignIn});

  /// Null hides the link: no accounts in this build, or someone is signed in.
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return _CenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Image.asset('assets/logo.png', width: 76, height: 76),
          ),
          const SizedBox(height: AppTheme.space20),
          Text(
            t.onboarding.welcomeTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            t.onboarding.welcomeBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          if (onSignIn != null) ...[
            const SizedBox(height: AppTheme.space20),
            TextButton(
              onPressed: onSignIn,
              child: Text(t.onboarding.signInLink),
            ),
          ],
        ],
      ),
    );
  }
}

/// The returning user's synced account is locked on this device: the passphrase
/// brings the machines, keys and snippets in. "Not now" goes back to the
/// server question.
class _UnlockSyncPage extends ConsumerStatefulWidget {
  const _UnlockSyncPage({
    required this.unlock,
    required this.onUnlocked,
    required this.onNotNow,
  });

  final Future<SyncReport> Function(String passphrase) unlock;
  final VoidCallback onUnlocked;
  final VoidCallback onNotNow;

  @override
  ConsumerState<_UnlockSyncPage> createState() => _UnlockSyncPageState();
}

class _UnlockSyncPageState extends ConsumerState<_UnlockSyncPage> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  SyncFailure? _failure;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  /// Unlocks, then reloads what came in and starts automatic sync, the same
  /// way the sync card does once it has unlocked.
  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.unlock(_passphrase.text);
      await ref.read(profilesProvider.notifier).loadProfiles();
      await ref.read(profileGroupsProvider.notifier).loadGroups();
      await ref.read(snippetsProvider.notifier).loadSnippets();
      ref.read(sshKeysRevisionProvider.notifier).bump();
      unawaited(ref.read(syncCoordinatorProvider).start());
    } on SyncException catch (error) {
      _fail(error.failure);
      return;
    } catch (_) {
      _fail(SyncFailure.unknown);
      return;
    }
    if (mounted) widget.onUnlocked();
  }

  void _fail(SyncFailure failure) {
    if (mounted) {
      setState(() {
        _failure = failure;
        _busy = false;
      });
    }
  }

  String _failureText(Translations t, SyncFailure failure) {
    final f = t.account.sync.failure;
    return switch (failure) {
      SyncFailure.wrongPassphrase => f.wrongPassphrase,
      SyncFailure.notPro => f.notPro,
      SyncFailure.network => f.network,
      SyncFailure.alreadySetUp => f.alreadySetUp,
      SyncFailure.turnedOff => f.turnedOff,
      SyncFailure.passphraseChanged => f.passphraseChanged,
      SyncFailure.unknown => f.unknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final failure = _failure;
    return _CenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.lockKey,
            regular: PhosphorIconsRegular.lockKey,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            t.onboarding.unlockTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            t.onboarding.unlockBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space24),
          AutofillGroup(
            child: AppFormField(
              controller: _passphrase,
              label: t.account.sync.passphrase,
              icon: PhosphorIconsRegular.key,
              obscure: true,
              action: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _unlock(),
            ),
          ),
          if (failure != null) ...[
            const SizedBox(height: AppTheme.space12),
            Text(
              _failureText(t, failure),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.colors.error),
            ),
          ],
          const SizedBox(height: AppTheme.space20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _unlock,
              child: Text(
                _busy ? t.account.sync.syncing : t.onboarding.unlockAction,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          TextButton(
            onPressed: _busy ? null : widget.onNotNow,
            child: Text(t.onboarding.notNow),
          ),
        ],
      ),
    );
  }
}

/// "Do you have a server?" Answering "not yet" opens the guide in place, so
/// the way to get one is on screen before the list it would go into.
class _ServerPage extends StatelessWidget {
  const _ServerPage({required this.answer, required this.onChanged});

  final ServerAnswer? answer;
  final ValueChanged<ServerAnswer> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return _CenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.hardDrives,
            regular: PhosphorIconsRegular.hardDrives,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            t.onboarding.serverTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            t.onboarding.serverBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space24),
          _ChoiceTile(
            icon: PhosphorIconsRegular.checkCircle,
            title: t.onboarding.serverYes,
            subtitle: t.onboarding.serverYesSubtitle,
            selected: answer == ServerAnswer.hasServer,
            onTap: () => onChanged(ServerAnswer.hasServer),
          ),
          const SizedBox(height: AppTheme.space10),
          _ChoiceTile(
            icon: PhosphorIconsRegular.question,
            title: t.onboarding.serverNotYet,
            subtitle: t.onboarding.serverNotYetSubtitle,
            selected: answer == ServerAnswer.notYet,
            onTap: () => onChanged(ServerAnswer.notYet),
          ),
          AnimatedSize(
            duration: AppTheme.motionSlow,
            curve: AppTheme.interactiveCurve,
            alignment: Alignment.topCenter,
            child: answer == ServerAnswer.notYet
                ? const Padding(
                    padding: EdgeInsets.only(top: AppTheme.space16),
                    child: ServerGuideList(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      elevated: true,
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.space14),
      child: Row(
        children: [
          Icon(icon, size: AppTheme.icon24, color: colors.primary),
          const SizedBox(width: AppTheme.space14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: colors.itemTitle),
                const SizedBox(height: AppTheme.space2),
                Text(
                  subtitle,
                  style: colors.uiSmall.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space8),
          Icon(
            selected
                ? PhosphorIconsRegular.checkCircle
                : PhosphorIconsRegular.circle,
            size: AppTheme.icon22,
            color: selected ? colors.primary : colors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// Approximates a Phosphor duotone glyph from the two weights this app
/// actually vendors: a large low-opacity fill behind a crisp regular-weight
/// outline in front, both in the brand color.
class _DuotoneIcon extends StatelessWidget {
  const _DuotoneIcon({required this.fill, required this.regular});

  static const double size = 56;

  final IconData fill;
  final IconData regular;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 1.8,
      height: size * 1.8,
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            fill,
            size: size,
            color: context.colors.primary.withValues(alpha: 0.35),
          ),
          Icon(regular, size: size * 0.72, color: context.colors.primary),
        ],
      ),
    );
  }
}

/// Scrolls when the content overflows, but centers it vertically when it
/// fits - a plain [SingleChildScrollView] always pins its child to the top.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - padding.vertical,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Two real, independently toggleable switches for the two OS-level
/// permissions - each one calls straight into the same service Settings
/// uses, so flipping one here has the exact same effect as flipping it
/// there later.
class _PermissionsPage extends StatefulWidget {
  const _PermissionsPage();

  @override
  State<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<_PermissionsPage>
    with WidgetsBindingObserver {
  bool _batteryUnrestricted = false;
  bool _notificationsGranted = false;

  /// Only iOS and Android 17 and up gate local traffic, so on anything older
  /// the row offers a permission that does not exist.
  bool _localNetworkEnforced = false;
  bool _localNetworkGranted = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The exemption is granted in a system dialog that reports nothing back, so
  /// the answer is re-read when the app comes forward again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final background = ForegroundNotificationService.instance;
    final batteryUnrestricted = await background.isIgnoringBatteryOptimizations;
    final notificationsGranted = await background.hasNotificationPermission;
    final localNetwork = LocalNetworkPermission.instance;
    final localNetworkEnforced = await localNetwork.isEnforced;
    final localNetworkGranted = await localNetwork.isGranted;
    if (!mounted) return;
    setState(() {
      _batteryUnrestricted = batteryUnrestricted;
      _notificationsGranted = notificationsGranted;
      _localNetworkEnforced = localNetworkEnforced;
      _localNetworkGranted = localNetworkGranted;
      _loaded = true;
    });
  }

  /// A refusal the system will not re-prompt for leaves the app's settings
  /// page as the only way in, the same as the notification permission beside
  /// it.
  Future<void> _onLocalNetworkTap() async {
    final localNetwork = LocalNetworkPermission.instance;
    if (_localNetworkGranted) {
      await localNetwork.openAppSettings();
    } else {
      final result = await localNetwork.request();
      if (result == LocalNetworkPermissionResult.permanentlyDenied) {
        await localNetwork.openAppSettings();
      }
    }
    await _load();
  }

  Future<void> _onBatteryTap() async {
    await ForegroundNotificationService.instance
        .requestIgnoreBatteryOptimization();
    await _load();
  }

  /// Once granted there is nothing left to ask for, so a tap opens the
  /// system's own settings screen instead - the only way to turn it back
  /// off.
  Future<void> _onNotificationsTap() async {
    final background = ForegroundNotificationService.instance;
    if (_notificationsGranted) {
      await background.openNotificationSettings();
      return;
    }
    await background.requestNotificationPermission();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return _CenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.shieldCheck,
            regular: PhosphorIconsRegular.shieldCheck,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            t.onboarding.permissionsTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            t.onboarding.permissionsBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space20),
          Opacity(
            opacity: _loaded ? 1 : 0.5,
            child: AppCard(
              clipChild: true,
              child: Material(
                color: context.colors.surfaceCard.invisible,
                child: Column(
                  children: [
                    if (isAndroidPlatform) ...[
                      PermissionTile(
                        dense: true,
                        title: t.onboarding.backgroundTitle,
                        subtitle: t.onboarding.backgroundSubtitle,
                        granted: _batteryUnrestricted,
                        onTap: _loaded ? _onBatteryTap : null,
                      ),
                      const AppDivider(indent: AppTheme.space14),
                    ],
                    PermissionTile(
                      dense: true,
                      title: t.onboarding.notificationsTitle,
                      subtitle: t.onboarding.notificationsSubtitle,
                      granted: _notificationsGranted,
                      onTap: _loaded ? _onNotificationsTap : null,
                    ),
                    if (_localNetworkEnforced) ...[
                      const AppDivider(indent: AppTheme.space14),
                      PermissionTile(
                        dense: true,
                        title: t.onboarding.localNetworkTitle,
                        subtitle: t.onboarding.localNetworkSubtitle,
                        granted: _localNetworkGranted,
                        onTap: _loaded ? _onLocalNetworkTap : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsPage extends StatelessWidget {
  const _AnalyticsPage({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return _CenteredScroll(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.chartLineUp,
            regular: PhosphorIconsRegular.chartLineUp,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            t.analyticsConsent.title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            t.analyticsConsent.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.space20),
          AppCard(
            clipChild: true,
            child: Material(
              color: context.colors.surfaceCard.invisible,
              child: SettingsCheckboxTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space14,
                ),
                title: t.analyticsConsent.checkboxLabel,
                value: checked,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space24),
          Text(
            t.analyticsConsent.legalNotice,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
          ),
          const SizedBox(height: AppTheme.space4),
          const _LegalLinks(),
        ],
      ),
    );
  }
}

/// The two published documents, side by side under the consent question.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegalLink(
          label: t.analyticsConsent.termsLink,
          url: LegalUrls.termsOfService,
        ),
        Text('·', style: TextStyle(color: context.colors.textTertiary)),
        _LegalLink(
          label: t.analyticsConsent.privacyLink,
          url: LegalUrls.privacyPolicy,
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => openExternalUrl(context, Uri.parse(url)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space10,
          vertical: AppTheme.space4,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.bodySmall,
      ),
      child: Text(label),
    );
  }
}

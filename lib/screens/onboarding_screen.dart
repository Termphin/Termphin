import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../i18n/strings.g.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app/legal_urls.dart';
import '../services/app/onboarding_service.dart';
import '../services/platform/foreground_notification_service.dart';
import '../services/ssh/local_network_permission.dart';
import '../theme/theme.dart';
import '../utils/platform_info.dart';
import '../widgets/profiles/server_guide.dart';
import '../widgets/ui/app_card.dart';
import '../widgets/ui/app_divider.dart';
import '../widgets/ui/clipboard_and_links.dart';
import '../widgets/ui/permission_tile.dart';
import '../widgets/ui/settings_tile.dart';

const _pageCount = 4;
const _serverPage = 1;

/// What onboarding was told about having a server, which decides where the
/// app goes once it closes.
enum ServerAnswer { hasServer, notYet }

/// First-launch flow: what Termphin is, whether there is a server to connect
/// to, permissions, then analytics consent.
///
/// The server question is the point of it. Most people who installed and never
/// connected had no machine to connect to, and the old flow never asked - it
/// ended on an empty list with a single add button.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final ValueChanged<ServerAnswer> onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// The server page is the one question that has to be answered to go on;
/// every other page can be swiped past.
class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _analyticsChecked = true;
  ServerAnswer? _answer;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AnalyticsService.instance.setConsent(_analyticsChecked);
    await OnboardingService.instance.markCompleted();
    widget.onComplete(_answer ?? ServerAnswer.notYet);
  }

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
                children: [
                  const _WelcomePage(),
                  _ServerPage(
                    answer: _answer,
                    onChanged: (a) => setState(() => _answer = a),
                  ),
                  const _PermissionsPage(),
                  _AnalyticsPage(
                    checked: _analyticsChecked,
                    onChanged: (v) => setState(() => _analyticsChecked = v),
                  ),
                ],
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
                      _pageCount,
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
                    canContinue: _page != _serverPage || _answer != null,
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
    required this.canContinue,
    required this.onBack,
    required this.onContinue,
    required this.onFinish,
  });

  final int page;
  final bool canContinue;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isLast = page == _pageCount - 1;
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
  const _WelcomePage();

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

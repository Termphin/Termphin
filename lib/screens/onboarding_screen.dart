import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../i18n/strings.g.dart';
import '../models/ssh_profile.dart';
import '../providers/anonymize_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/ssh_keys_provider.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app/identity_anonymizer.dart';
import '../services/app/legal_urls.dart';
import '../services/app/onboarding_service.dart';
import '../services/platform/foreground_notification_service.dart';
import '../services/ssh/local_network_permission.dart';
import '../services/ssh/ssh_config_import.dart';
import '../services/ssh/ssh_link.dart';
import '../services/storage/group_storage.dart';
import '../theme/theme.dart';
import '../utils/platform_info.dart';
import '../widgets/profiles/server_guide.dart';
import '../widgets/ui/app_card.dart';
import '../widgets/ui/app_divider.dart';
import '../widgets/ui/clipboard_and_links.dart';
import '../widgets/ui/key_caps.dart';
import '../widgets/ui/permission_tile.dart';

const _serverPage = 1;

/// The permissions page asks for what the system gates. A desktop gates none
/// of it, and a page of nothing to grant is a page to skip.
bool get _hasPermissionsPage =>
    platformHas(PlatformFeature.notificationPermission) ||
    platformHas(PlatformFeature.foregroundService) ||
    platformHas(PlatformFeature.localNetworkPermission);

int get _pageCount => _hasPermissionsPage ? 4 : 3;

/// What onboarding was told about having a server, which decides where the
/// app goes once it closes.
enum ServerAnswer { hasServer, notYet }

/// What onboarding ended with, which decides where the app goes next.
class OnboardingResult {
  const OnboardingResult(this.answer, {this.target, this.imported = 0});

  final ServerAnswer answer;

  /// A machine typed in on the way through, to open the form filled in with.
  final SshLink? target;

  /// How many machines were brought in from `~/.ssh/config`.
  final int imported;
}

/// Reads the hosts onboarding can offer to import; [existing] are the
/// machines already in the list. A test stands in for the disk with it.
typedef SshConfigLoader =
    Future<List<SshConfigCandidate>> Function(Set<String> existing);

/// First-launch flow: what Termphin is, whether there is a server to connect
/// to, permissions, then analytics consent.
///
/// The server question is the point of it. Most people who installed and never
/// connected had no machine to connect to, and the old flow never asked - it
/// ended on an empty list with a single add button.
///
/// A desktop gets its own shape, [_DesktopOnboarding]: a carousel of pages
/// with dots is a phone's, and reads as a phone stretched over a window.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.sshConfigLoader,
  });

  final ValueChanged<OnboardingResult> onComplete;

  @visibleForTesting
  final SshConfigLoader? sshConfigLoader;

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
    widget.onComplete(OnboardingResult(_answer ?? ServerAnswer.notYet));
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
    if (isDesktopPlatform) {
      return _DesktopOnboarding(
        onComplete: widget.onComplete,
        sshConfigLoader: widget.sshConfigLoader,
      );
    }
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
                  if (_hasPermissionsPage) const _PermissionsPage(),
                  _AnalyticsPage(
                    checked: _analyticsChecked,
                    onChanged: (v) => setState(() => _analyticsChecked = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pageCount,
                      (index) => AnimatedContainer(
                        duration: AppTheme.motionSlow,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: index == _page ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: index == _page
                              ? context.colors.primary
                              : context.colors.surfaceBorder,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Image.asset('assets/logo.png', width: 76, height: 76),
          ),
          const SizedBox(height: 20),
          Text(
            t.onboarding.welcomeTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.hardDrives,
            regular: PhosphorIconsRegular.hardDrives,
          ),
          const SizedBox(height: 16),
          Text(
            t.onboarding.serverTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            t.onboarding.serverBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _ChoiceTile(
            icon: PhosphorIconsRegular.checkCircle,
            title: t.onboarding.serverYes,
            subtitle: t.onboarding.serverYesSubtitle,
            selected: answer == ServerAnswer.hasServer,
            onTap: () => onChanged(ServerAnswer.hasServer),
          ),
          const SizedBox(height: 10),
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
                    padding: EdgeInsets.only(top: 16),
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
    this.keyHint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// The key that picks this one on a desktop, drawn as a keycap.
  final String? keyHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.08)
                : colors.surfaceElevated,
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.primary : colors.surfaceBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: colors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: colors.itemTitle),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: colors.uiSmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (keyHint case final hint?) ...[
                KeyCaps([hint]),
                const SizedBox(width: 10),
              ],
              Icon(
                selected
                    ? PhosphorIconsRegular.checkCircle
                    : PhosphorIconsRegular.circle,
                size: 22,
                color: selected ? colors.primary : colors.textTertiary,
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.shieldCheck,
            regular: PhosphorIconsRegular.shieldCheck,
          ),
          const SizedBox(height: 16),
          Text(
            t.onboarding.permissionsTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            t.onboarding.permissionsBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Opacity(
            opacity: _loaded ? 1 : 0.5,
            child: AppCard(
              clipChild: true,
              child: Material(
                color: context.colors.surfaceCard.invisible,
                child: Column(
                  children: [
                    if (platformHas(PlatformFeature.foregroundService)) ...[
                      PermissionTile(
                        dense: true,
                        title: t.onboarding.backgroundTitle,
                        subtitle: t.onboarding.backgroundSubtitle,
                        granted: _batteryUnrestricted,
                        onTap: _loaded ? _onBatteryTap : null,
                      ),
                      const AppDivider(indent: 14),
                    ],
                    PermissionTile(
                      dense: true,
                      title: t.onboarding.notificationsTitle,
                      subtitle: t.onboarding.notificationsSubtitle,
                      granted: _notificationsGranted,
                      onTap: _loaded ? _onNotificationsTap : null,
                    ),
                    if (_localNetworkEnforced) ...[
                      const AppDivider(indent: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DuotoneIcon(
            fill: PhosphorIconsFill.chartLineUp,
            regular: PhosphorIconsRegular.chartLineUp,
          ),
          const SizedBox(height: 16),
          Text(
            t.analyticsConsent.title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            t.analyticsConsent.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            clipChild: true,
            child: Material(
              color: context.colors.surfaceCard.invisible,
              child: CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  t.analyticsConsent.checkboxLabel,
                  style: const TextStyle(fontSize: 14),
                ),
                value: checked,
                checkColor: context.colors.onPrimary,
                fillColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? context.colors.primary
                      : null,
                ),
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            t.analyticsConsent.legalNotice,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
          ),
          const SizedBox(height: 4),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.bodySmall,
      ),
      child: Text(label),
    );
  }
}

/// Onboarding on a desktop: one panel in the middle of the window, the steps
/// listed down its side, worked from the keyboard - Enter goes on, Esc goes
/// back, 1 and 2 answer the server question.
///
/// The server step is where it earns its place there. A desktop user usually
/// has `~/.ssh/config` and the keys beside it already, so the hosts in it are
/// offered to bring in as they are; a machine can also be typed the way it is
/// after `ssh`, and the form opens on it filled in.
///
/// The panel's border is drawn over the content, not under it: the step rail
/// has a background of its own, and under it the border was painted over
/// where the corners curve.
class _DesktopOnboarding extends ConsumerStatefulWidget {
  const _DesktopOnboarding({required this.onComplete, this.sshConfigLoader});

  final ValueChanged<OnboardingResult> onComplete;
  final SshConfigLoader? sshConfigLoader;

  @override
  ConsumerState<_DesktopOnboarding> createState() => _DesktopOnboardingState();
}

class _DesktopOnboardingState extends ConsumerState<_DesktopOnboarding> {
  static const _welcome = 0;
  static const _server = 1;
  static const _privacy = 2;

  final _focus = FocusNode(debugLabel: 'desktopOnboarding');
  final _target = TextEditingController();
  final _targetFocus = FocusNode();
  int _step = _welcome;
  ServerAnswer? _answer;
  bool _analyticsChecked = true;
  bool _targetInvalid = false;
  bool _finishing = false;

  /// What `~/.ssh/config` holds, and which of it is ticked.
  List<SshConfigCandidate> _candidates = const [];
  final _picked = <String>{};

  @override
  void initState() {
    super.initState();
    _loadSshConfig();
  }

  @override
  void dispose() {
    _focus.dispose();
    _target.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  /// Offers the hosts of `~/.ssh/config`. Everything that can come in as it
  /// is starts ticked, since it is the user's own list of machines. No config
  /// to offer is the same as an unreadable one: the step still takes a typed
  /// address.
  Future<void> _loadSshConfig() async {
    try {
      final notifier = ref.read(profilesProvider.notifier);
      await notifier.loadProfiles();
      final existing = {
        for (final p in ref.read(profilesProvider))
          sshConfigIdentity(p.username, p.host, p.port),
      };
      final loader = widget.sshConfigLoader;
      final List<SshConfigCandidate> found;
      if (loader != null) {
        found = await loader(existing);
      } else {
        final home = sshHomeDirectory();
        found = home == null
            ? const []
            : await readSshConfigCandidates(home: home, existing: existing);
      }
      if (!mounted) return;
      setState(() {
        _candidates = found;
        _picked
          ..clear()
          ..addAll([
            for (final c in found)
              if (c.importable) c.host.alias,
          ]);
      });
    } on Object {
      return;
    }
  }

  bool get _canContinue => _step != _server || _answer != null;

  void _answerWith(ServerAnswer answer) {
    setState(() => _answer = answer);
    if (answer == ServerAnswer.hasServer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _targetFocus.requestFocus();
      });
    } else {
      _focus.requestFocus();
    }
  }

  /// The address typed on the server step, when there is one and it reads.
  SshLink? get _typedTarget =>
      _answer == ServerAnswer.hasServer ? parseSshTarget(_target.text) : null;

  void _continue() {
    if (!_canContinue || _finishing) return;
    if (_step == _server && _answer == ServerAnswer.hasServer) {
      final invalid = _target.text.trim().isNotEmpty && _typedTarget == null;
      setState(() => _targetInvalid = invalid);
      if (invalid) return;
    }
    if (_step == _privacy) {
      _finish();
      return;
    }
    setState(() => _step++);
    _focus.requestFocus();
  }

  void _back() {
    if (_step == _welcome || _finishing) return;
    setState(() => _step--);
    _focus.requestFocus();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await AnalyticsService.instance.setConsent(_analyticsChecked);
    final imported = _answer == ServerAnswer.hasServer
        ? await _importPicked()
        : 0;
    await OnboardingService.instance.markCompleted();
    widget.onComplete(
      OnboardingResult(
        _answer ?? ServerAnswer.notYet,
        target: _typedTarget,
        imported: imported,
      ),
    );
  }

  /// Adds the ticked hosts, each with its key - one key once, however many
  /// hosts sign in with it. A host whose key will not import is left out
  /// rather than added half-made.
  Future<int> _importPicked() async {
    final picked = [
      for (final c in _candidates)
        if (c.importable && _picked.contains(c.host.alias)) c,
    ];
    if (picked.isEmpty) return 0;
    final storage = ref.read(sshKeyStorageProvider);
    final profiles = ref.read(profilesProvider.notifier);
    final keyIds = <String, String?>{};
    var imported = 0;
    var keysAdded = false;
    for (final candidate in picked) {
      final path = candidate.keyPath!;
      final pem = candidate.keyPem!;
      if (!keyIds.containsKey(path)) {
        try {
          final known = await storage.loadKeys();
          final same = known.where((k) => k.privateKeyPem.trim() == pem);
          if (same.isNotEmpty) {
            keyIds[path] = same.first.id;
          } else {
            final name = path.split(RegExp(r'[\\/]')).last;
            final key = await storage.importFromPem(
              name,
              pem,
              group: GroupStorage.defaultGroup,
            );
            keyIds[path] = key.id;
            keysAdded = true;
          }
        } on Object {
          keyIds[path] = null;
        }
      }
      final keyId = keyIds[path];
      if (keyId == null) continue;
      try {
        await profiles.addProfile(
          name: candidate.host.alias,
          host: candidate.host.hostName,
          port: candidate.host.port,
          username: candidate.username,
          authMethod: AuthMethod.privateKey,
          sshKeyId: keyId,
        );
        imported++;
      } on Object {
        continue;
      }
    }
    if (keysAdded) ref.read(sshKeysRevisionProvider.notifier).bump();
    return imported;
  }

  /// Esc goes back from anywhere. Enter and the digits are left to a text
  /// field while one has focus, since it has its own Enter and its own
  /// digits.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_step == _welcome) return KeyEventResult.ignored;
      _back();
      return KeyEventResult.handled;
    }
    final typing =
        FocusManager.instance.primaryFocus?.context?.widget is EditableText;
    if (typing) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _continue();
      return KeyEventResult.handled;
    }
    if (_step == _server) {
      if (key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.numpad1) {
        _answerWith(ServerAnswer.hasServer);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2 ||
          key == LogicalKeyboardKey.numpad2) {
        _answerWith(ServerAnswer.notYet);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final steps = [
      t.onboarding.stepWelcome,
      t.onboarding.stepServer,
      t.onboarding.stepPrivacy,
    ];
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 560),
              child: Container(
                key: const ValueKey('desktopOnboarding'),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surfaceCard,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepRail(steps: steps, current: _step),
                    VerticalDivider(width: 1, color: colors.surfaceBorder),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: AppTheme.interactiveDuration,
                              child: KeyedSubtree(
                                key: ValueKey(_step),
                                child: _stepBody(t),
                              ),
                            ),
                          ),
                          Divider(height: 1, color: colors.surfaceBorder),
                          _footer(t),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(Translations t) => switch (_step) {
    _welcome => _DesktopWelcome(body: t.onboarding.welcomeBodyDesktop),
    _server => _serverStep(t),
    _ => _AnalyticsPage(
      checked: _analyticsChecked,
      onChanged: (v) => setState(() => _analyticsChecked = v),
    ),
  };

  Widget _footer(Translations t) {
    final colors = context.colors;
    final hint = colors.uiSmall.copyWith(
      fontSize: 11.5,
      color: colors.textTertiary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          if (_step > _welcome) ...[
            TextButton(
              key: const ValueKey('onboardingBack'),
              onPressed: _finishing ? null : _back,
              child: Text(t.onboarding.back),
            ),
            const SizedBox(width: 6),
            const KeyCaps(['Esc']),
          ],
          const Spacer(),
          const KeyCaps(['Enter']),
          const SizedBox(width: 6),
          Text(
            _step == _privacy
                ? t.onboarding.keyFinish
                : t.onboarding.keyContinue,
            style: hint,
          ),
          const SizedBox(width: 14),
          FilledButton(
            key: const ValueKey('onboardingContinue'),
            onPressed: _canContinue && !_finishing ? _continue : null,
            child: Text(switch (_step) {
              _welcome => t.onboarding.getStarted,
              _privacy => t.onboarding.finish,
              _ => t.onboarding.continueAction,
            }),
          ),
        ],
      ),
    );
  }

  Widget _serverStep(Translations t) {
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.onboarding.serverTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            t.onboarding.serverBody,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 18),
          _ChoiceTile(
            icon: PhosphorIconsRegular.checkCircle,
            title: t.onboarding.serverYes,
            subtitle: t.onboarding.serverYesSubtitle,
            selected: _answer == ServerAnswer.hasServer,
            keyHint: '1',
            onTap: () => _answerWith(ServerAnswer.hasServer),
          ),
          const SizedBox(height: 10),
          _ChoiceTile(
            icon: PhosphorIconsRegular.question,
            title: t.onboarding.serverNotYet,
            subtitle: t.onboarding.serverNotYetSubtitle,
            selected: _answer == ServerAnswer.notYet,
            keyHint: '2',
            onTap: () => _answerWith(ServerAnswer.notYet),
          ),
          if (_answer == ServerAnswer.hasServer) ...[
            const SizedBox(height: 18),
            Text(t.onboarding.targetLabel, style: colors.itemTitle),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('onboardingTarget'),
              controller: _target,
              focusNode: _targetFocus,
              autocorrect: false,
              enableSuggestions: false,
              style: colors.monoStyle.copyWith(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: t.profiles.quickAddHint,
                helperText: t.onboarding.targetHelper,
                errorText: _targetInvalid ? t.profiles.quickAddInvalid : null,
              ),
              onChanged: (_) {
                if (_targetInvalid) setState(() => _targetInvalid = false);
              },
              onSubmitted: (_) => _continue(),
            ),
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sshConfigList(t),
            ],
          ],
          if (_answer == ServerAnswer.notYet)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: ServerGuideList(),
            ),
        ],
      ),
    );
  }

  Widget _sshConfigList(Translations t) {
    final colors = context.colors;
    final anonymize = ref.watch(anonymizeProvider);
    String reason(SshConfigProblem problem) => switch (problem) {
      SshConfigProblem.noKey => t.onboarding.sshConfigNoKey,
      SshConfigProblem.encryptedKey => t.onboarding.sshConfigEncrypted,
      SshConfigProblem.unreadableKey => t.onboarding.sshConfigUnreadable,
      SshConfigProblem.alreadyAdded => t.onboarding.sshConfigAlready,
    };
    return Column(
      key: const ValueKey('onboardingSshConfig'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.onboarding.sshConfigTitle, style: colors.itemTitle),
        const SizedBox(height: 3),
        Text(
          t.onboarding.sshConfigSubtitle,
          style: colors.uiSmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        AppCard(
          clipChild: true,
          child: Material(
            color: colors.surfaceCard.invisible,
            child: Column(
              children: [
                for (final (i, c) in _candidates.indexed) ...[
                  if (i > 0) const AppDivider(indent: 14),
                  CheckboxListTile(
                    key: ValueKey('sshConfigHost-${c.host.alias}'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    value: c.importable && _picked.contains(c.host.alias),
                    checkColor: Colors.white,
                    fillColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.selected)
                          ? colors.primary
                          : null,
                    ),
                    onChanged: c.importable
                        ? (v) => setState(
                            () => v ?? false
                                ? _picked.add(c.host.alias)
                                : _picked.remove(c.host.alias),
                          )
                        : null,
                    title: Text(
                      anonymize
                          ? IdentityAnonymizer.name(c.host.alias)
                          : c.host.alias,
                      style: colors.itemTitle.copyWith(
                        fontSize: 14,
                        color: c.importable ? null : colors.textTertiary,
                      ),
                    ),
                    subtitle: Text(
                      [
                        anonymize
                            ? '${IdentityAnonymizer.username(c.host.alias)}@'
                                  '${IdentityAnonymizer.host(c.host.alias)}'
                            : '${c.username}@${c.host.hostName}',
                        if (c.host.port != 22) ':${c.host.port}',
                        if (c.problem case final problem?)
                          ' · ${reason(problem)}',
                      ].join(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: colors.monoSmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The steps down the panel's side: done, current, still to come.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      width: 212,
      color: colors.backgroundPrimary,
      padding: const EdgeInsets.fromLTRB(22, 26, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset('assets/logo.png', width: 28, height: 28),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Translations.of(context).window.menuApp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.itemTitle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          for (final (i, label) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: AppTheme.interactiveDuration,
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= current
                          ? colors.primary
                          : colors.primary.invisible,
                      border: Border.all(
                        color: i <= current
                            ? colors.primary
                            : colors.surfaceBorderStrong,
                      ),
                    ),
                    child: i < current
                        ? Icon(
                            PhosphorIconsRegular.check,
                            size: 12,
                            color: onPrimary,
                          )
                        : Text(
                            '${i + 1}',
                            style: colors.uiSmall.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: i == current
                                  ? onPrimary
                                  : colors.textTertiary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      key: ValueKey('onboardingStep-$i'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: colors.uiStyle.copyWith(
                        fontWeight: i == current
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: i == current
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The welcome step, set from the left as the rest of the panel is.
class _DesktopWelcome extends StatelessWidget {
  const _DesktopWelcome({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Image.asset('assets/logo.png', width: 64, height: 64),
          ),
          const SizedBox(height: 22),
          Text(
            t.onboarding.welcomeTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

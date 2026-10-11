import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'i18n/strings.g.dart';
import 'models/ssh_profile.dart';
import 'providers/groups_provider.dart';
import 'providers/profiles_provider.dart';
import 'providers/snippets_provider.dart';
import 'providers/terminal_overlay_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/lock_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/analytics/analytics_service.dart';
import 'services/app/onboarding_service.dart';
import 'services/app/review_prompt_service.dart';
import 'services/app/tag_migration_service.dart';
import 'services/app/whats_new_service.dart';
import 'services/platform/quick_actions_service.dart';
import 'services/security/lock_service.dart';
import 'services/security/relock_guard.dart';
import 'services/settings/toolbar_share_link.dart';
import 'services/ssh/ssh_link.dart';
import 'theme/theme.dart';
import 'utils/platform_info.dart';
import 'widgets/onboarding/tag_migration_modal.dart';
import 'widgets/onboarding/whats_new_modal.dart';
import 'widgets/profiles/profile_avatar.dart';
import 'widgets/profiles/profile_form_dialog.dart';
import 'widgets/terminal/toolbar_import_sheet.dart';
import 'widgets/ui/app_notifications.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class SshClientApp extends StatelessWidget {
  const SshClientApp({super.key, this.home});

  /// What opens instead of the app itself - the share screen, which runs in
  /// an engine of its own with the same theme, strings and navigator.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      retry: (_, _) => null,
      child: TranslationProvider(child: _AppRoot(home: home)),
    );
  }
}

class _AppRoot extends ConsumerWidget {
  const _AppRoot({this.home});

  final Widget? home;

  /// The share screen asks for the PIN itself and never outlives one share,
  /// so only the app proper can be locked again.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final wideLayout = isWideLayout(context);
    return MaterialApp(
      title: 'Termphin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(AppColors.light, wideLayout: wideLayout),
      darkTheme: AppTheme.themeFor(AppColors.dark, wideLayout: wideLayout),
      themeMode: themeMode.themeMode,
      navigatorKey: navigatorKey,
      home: home ?? const _AppGate(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemOverlayStyleFor(context.colors),
        child: _ScaledMediaQuery(
          child: home == null
              ? _RelockLayer(child: child ?? const SizedBox.shrink())
              : child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// The lock screen [RelockGuard] puts back, over the navigator rather than
/// inside it, so no route, dialog or connection prompt can be drawn above it.
///
/// The app under it stays mounted - its sessions keep running and nothing
/// has to be rebuilt after the PIN - but off stage, without focus or tickers:
/// it neither paints nor takes a key. The lock screen sits in an overlay of
/// its own, beside the navigator rather than under it, since it has none to
/// borrow.
class _RelockLayer extends StatelessWidget {
  const _RelockLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final guard = RelockGuard.instance;
    return ListenableBuilder(
      listenable: guard,
      builder: (context, _) {
        final locked = guard.locked;
        return Stack(
          fit: StackFit.expand,
          children: [
            TickerMode(
              enabled: !locked,
              child: Offstage(
                offstage: locked,
                child: ExcludeFocus(excluding: locked, child: child),
              ),
            ),
            if (locked)
              Overlay.wrap(
                key: const ValueKey('relockOverlay'),
                child: LockScreen(onUnlocked: guard.unlocked),
              ),
          ],
        );
      },
    );
  }
}

/// Bounds the system font scale for the whole app.
///
/// Android's font-size slider reaches 2.0, and Display size shrinks the
/// viewport on top of that. A terminal client is dense by nature - tab strip,
/// key toolbar and nav bar all compete for the same screen - and at the far
/// end of that range they stop fitting rather than merely looking large.
/// Clamping keeps every one of them legible without any of them collapsing,
/// and the place where big text actually matters, the terminal itself, has
/// its own font size in settings that this does not touch.
class _ScaledMediaQuery extends StatelessWidget {
  const _ScaledMediaQuery({required this.child});

  static const _minScale = 0.85;
  static const _maxScale = 1.3;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final query = MediaQuery.of(context);
    return MediaQuery(
      data: query.copyWith(
        textScaler: query.textScaler.clamp(
          minScaleFactor: _minScale,
          maxScaleFactor: _maxScale,
        ),
      ),
      child: child,
    );
  }
}

/// Checks onboarding and lock state on startup. Shows OnboardingScreen once,
/// then LockScreen if a PIN is set, otherwise goes straight to the app.
class _AppGate extends ConsumerStatefulWidget {
  const _AppGate();

  @override
  ConsumerState<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<_AppGate> {
  final _appLinks = AppLinks();
  StreamSubscription<String>? _linkSub;
  String? _pendingLink;
  String? _lastLink;
  DateTime? _lastLinkTime;

  bool _needsOnboarding = false;
  bool _locked = false;
  bool _checked = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: RelockGuard.instance.appHidden,
      onShow: RelockGuard.instance.appShown,
    );
    _initLinkHandling();
    _checkGate();
  }

  void _initLinkHandling() {
    _linkSub = _appLinks.stringLinkStream.listen(_onLinkReceived);
    unawaited(_checkInitialLink());
  }

  /// Opens the link the app was launched with, if any. A missing platform
  /// channel or any other failure to read it just means there is no link.
  Future<void> _checkInitialLink() async {
    try {
      final initial = await _appLinks.getInitialLinkString();
      if (initial != null && mounted) {
        _onLinkReceived(initial);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _linkSub?.cancel();
    _linkSub = null;
    super.dispose();
  }

  Future<void> _checkGate() async {
    final needsOnboarding = !await OnboardingService.instance.isCompleted();
    final enabled = await LockService.instance.isLockEnabled;
    if (!mounted) return;
    setState(() {
      _needsOnboarding = needsOnboarding;
      _locked = enabled;
      _checked = true;
    });
    if (!enabled) unawaited(RelockGuard.instance.arm());
    _flushPendingLinkIfReady();
  }

  /// A link that opened the app already says which machine to add, so it
  /// takes priority over the onboarding answer. Otherwise, someone who says
  /// they have a machine goes straight to the form rather than to an empty
  /// list with a button on it.
  void _onOnboardingComplete(ServerAnswer answer) {
    setState(() => _needsOnboarding = false);
    if (_pendingLink != null) {
      _flushPendingLinkIfReady();
      return;
    }
    if (answer == ServerAnswer.hasServer) _openFirstProfileForm();
  }

  void _openFirstProfileForm() {
    final nav = navigatorKey.currentState;
    if (nav == null || _locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _locked) return;
        _openFirstProfileForm();
      });
      return;
    }
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const ProfileFormDialog(),
        fullscreenDialog: true,
      ),
    );
  }

  void _onUnlocked() {
    setState(() => _locked = false);
    unawaited(RelockGuard.instance.arm());
    _flushPendingLinkIfReady();
  }

  /// Holds the link until the app is unlocked, to avoid leaking the machine
  /// address on the lock screen; if it locks again before that, the form it
  /// opens waits as the first thing on screen after the PIN.
  void _onLinkReceived(String linkStr) {
    final now = DateTime.now();
    if (_lastLink == linkStr &&
        _lastLinkTime != null &&
        now.difference(_lastLinkTime!) < const Duration(seconds: 1)) {
      return;
    }
    _lastLink = linkStr;
    _lastLinkTime = now;

    if (!_checked || _locked || _needsOnboarding) {
      _pendingLink = linkStr;
      return;
    }
    RelockGuard.instance.whenUnlocked(() {
      if (mounted) _openLink(linkStr);
    });
  }

  void _flushPendingLinkIfReady() {
    if (!_checked || _locked || _needsOnboarding) return;
    final link = _pendingLink;
    if (link == null) return;
    _pendingLink = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openLink(link);
    });
  }

  /// A shared toolbar only ever asks: nothing is added until the sheet has
  /// shown what its keys type and the user has said yes.
  void _openLink(String linkStr) {
    final nav = navigatorKey.currentState;
    final navContext = navigatorKey.currentContext;
    if (nav == null || navContext == null || !navContext.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openLink(linkStr);
      });
      return;
    }

    final t = Translations.of(navContext);
    if (isToolbarShareLink(linkStr)) {
      final share = parseToolbarShareLink(linkStr);
      if (share == null) {
        AppNotifications.error(navContext, t.toolbar.importInvalid);
      } else {
        unawaited(showToolbarImportSheet(navContext, share));
      }
      return;
    }

    final parsed = parseSshLink(linkStr);
    if (parsed == null) {
      AppNotifications.error(navContext, t.profileForm.linkInvalid);
      return;
    }

    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileFormDialog(prefill: parsed),
        fullscreenDialog: true,
      ),
    );
    AppNotifications.success(navContext, t.profileForm.linkPrefilled);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        backgroundColor: context.colors.backgroundPrimary,
        body: const SizedBox.shrink(),
      );
    }
    if (_needsOnboarding) {
      return OnboardingScreen(onComplete: _onOnboardingComplete);
    }
    if (_locked) {
      return LockScreen(onUnlocked: _onUnlocked);
    }
    return const _AppShell();
  }
}

/// Wraps the home screen. When active SSH sessions exist and user presses
/// back on the root screen, minimize the app instead of closing it.
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  @override
  void initState() {
    super.initState();
    final service = QuickActionsService.instance;
    service.isReady = () => navigatorKey.currentContext?.mounted ?? false;
    service.onOpenProfile = _openQuickActionProfile;
    service.iconIds = ProfileAvatarData.icons.map((icon) => icon.id).toList();
    service.normalizeColorHex = (hex) => ProfileAvatarColor.forHex(hex).hex;
    service.init();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _runStartupInterstitials(),
    );
  }

  /// What a quick-action shortcut does once it is allowed through: the same
  /// as tapping the machine on the home screen.
  void _openQuickActionProfile(SshProfile profile) {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    ProviderScope.containerOf(
      context,
    ).read(terminalOverlayProvider.notifier).openProfile(profile);
  }

  /// What the home screen may interrupt with, in order: what changed, then the
  /// one question this release has to ask, then - only if neither of those
  /// spoke - the store prompt.
  ///
  /// The review dialog never stacks on another modal: two interstitials get
  /// both dismissed unread. The tag conversion is not subject to that budget,
  /// because it is a question about the user's own data rather than an
  /// announcement, and skipping it would leave the data half-migrated.
  ///
  /// It runs here rather than in `_AppGate` so it lands after what's new. That
  /// means the home screen has already read the group list by the time it is
  /// answered, which is why `TagMigrationService.apply` sets that list rather
  /// than adding to it.
  Future<void> _runStartupInterstitials() async {
    final packageInfo = await PackageInfo.fromPlatform();

    final highlights = await WhatsNewService.instance.pendingSince(
      packageInfo.version,
    );
    if (!mounted) return;
    var interrupted = false;
    if (highlights.isNotEmpty) {
      await showWhatsNewModal(context, highlights);
      await WhatsNewService.instance.markSeen(highlights);
      interrupted = true;
    }

    final migration = TagMigrationService();
    if (await migration.isPending()) {
      final plan = await migration.detect();
      if (!mounted) return;
      if (!plan.isEmpty) {
        await showTagMigrationModal(context, plan, service: migration);
        if (!mounted) return;
        await ref.read(profileGroupsProvider.notifier).loadGroups();
        await ref.read(profilesProvider.notifier).loadProfiles();
        await ref.read(snippetsProvider.notifier).loadSnippets();
        interrupted = true;
      }
    }

    if (interrupted) return;
    if (await ReviewPromptService.instance.maybePrompt(packageInfo.version)) {
      unawaited(
        AnalyticsService.instance.capture(AnalyticsEvent.reviewPromptRequested),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    QuickActionsService.instance.update(profiles);
    return const MainShell();
  }
}

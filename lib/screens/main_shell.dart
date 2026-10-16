import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../i18n/strings.g.dart';
import '../models/active_session.dart';
import '../models/ssh_profile.dart';
import '../providers/anonymize_provider.dart';
import '../providers/ssh_session_manager_provider.dart';
import '../providers/terminal_overlay_provider.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app/identity_anonymizer.dart';
import '../services/settings/sidebar_settings.dart';
import '../services/settings/tab_bar_settings.dart';
import '../services/ssh/ssh_session_manager.dart';
import '../theme/theme.dart';
import '../utils/platform_info.dart';
import '../widgets/profiles/profile_avatar.dart';
import '../widgets/shell/nav_rail.dart';
import '../widgets/terminal/terminal_scheme_theme.dart';
import '../widgets/ui/app_badge.dart';
import '../widgets/ui/app_notifications.dart';
import '../widgets/ui/fade_over_color.dart';
import 'home_screen.dart';
import 'keys/key_manager_screen.dart';
import 'settings/settings_screen.dart';
import 'snippets/snippets_screen.dart';
import 'terminal/terminal_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

/// Reusing an already-visible terminal strip only gains a tab; tearing it
/// down and remounting from `initState` would restart every other tab's
/// connection along with it. Only a cold `TerminalScreen` with no live state
/// behind it - first launch, or right after the strip fully closed - gets a
/// fresh key so `initState` has something to build.
///
/// With nothing left to intercept, back belongs to Android: a blanket
/// `canPop: false` reports "framework handles back" for the whole app and
/// costs the system its predictive back-to-home animation.
class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  late final SshSessionManager _manager = ref.read(sshSessionManagerProvider);

  int _currentIndex = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    SnippetsScreen(),
    KeyManagerScreen(),
    SettingsScreen(),
  ];

  /// Screen views for the four destinations are reported from here rather
  /// than from each screen's `initState`: all four are mounted at once behind
  /// [_AnimatedNavBody], so a per-screen hook would report every one of them
  /// on the first frame and never again.
  static const _screenNames = <AnalyticsScreen>[
    AnalyticsScreen.home,
    AnalyticsScreen.snippets,
    AnalyticsScreen.keyManager,
    AnalyticsScreen.settings,
  ];

  (String, SshProfile)? _terminalSession;
  SiblingScope _siblingScope = SiblingScope.all;
  bool _terminalVisible = false;
  GlobalKey<TerminalScreenState> _terminalKey =
      GlobalKey<TerminalScreenState>();

  /// Brings the terminal up over the tabs and takes it back down, along
  /// Material's shared Z axis: the tabs drift away and fade out, then the
  /// terminal comes forward and fades in; hiding plays it back, quicker. The
  /// two never fade at the same time, so nothing is ever half of each - which
  /// is what lets [FadeOverColorTransition] do the fading with a plain
  /// colour instead of an offscreen layer per frame. A
  /// closed strip is only dropped once it has gone, so closing animates too.
  late final AnimationController _terminalMotion;
  late final Animation<double> _terminalCurve = CurvedAnimation(
    parent: _terminalMotion,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: Easing.emphasizedAccelerate,
  );

  /// The terminal fades in over the last part of the way in, after the tabs
  /// are gone, and out over the first part of the way back.
  late final Animation<double> _terminalFade = CurvedAnimation(
    parent: _terminalMotion,
    curve: const Interval(_handover, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(1 - _handover, 1, curve: Curves.easeIn),
  );

  /// The tabs fade out over the first part of the way in and back in over
  /// the last part of the way back - the mirror of [_terminalFade].
  late final Animation<double> _backgroundFade = ReverseAnimation(
    CurvedAnimation(
      parent: _terminalMotion,
      curve: const Interval(0, _handover, curve: Curves.easeIn),
      reverseCurve: const Interval(0, 1 - _handover, curve: Curves.easeOut),
    ),
  );
  late final Animation<double> _terminalScale = Tween(
    begin: _zDepth,
    end: 1.0,
  ).animate(_terminalCurve);
  late final Animation<double> _backgroundScale = Tween(
    begin: 1.0,
    end: 2 - _zDepth,
  ).animate(_terminalCurve);

  /// Where along the motion one screen hands over to the other.
  static const double _handover = 0.3;

  /// How far back the terminal starts, as a scale; the tabs move forward by
  /// the same step, so both read as one camera moving along the axis.
  static const double _zDepth = 0.92;

  /// Bumped whenever the terminal is asked back, so a close still waiting
  /// for its exit to finish knows not to drop the strip after all.
  var _closeGeneration = 0;

  void _animateTerminal({required bool visible}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _terminalMotion.value = visible ? 1 : 0;
    } else if (visible) {
      unawaited(_terminalMotion.forward());
    } else {
      unawaited(_terminalMotion.reverse());
    }
  }

  /// Starts the terminal's entrance one frame late. The frame a terminal is
  /// requested in is the one that builds it - a new screen, a new tab, its
  /// connection set up - and an entrance started in it would spend its
  /// first frames waiting on that. Built first, still invisible, the motion
  /// then has every frame to itself.
  void _animateTerminalAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _terminalVisible) _animateTerminal(visible: true);
    });
  }

  @override
  void initState() {
    super.initState();
    final restored = _manager.lastActiveSession;
    if (restored != null) {
      _terminalSession = (restored.id, restored.profile);
      _terminalVisible = true;
    }
    _terminalMotion = AnimationController(
      vsync: this,
      duration: AppTheme.motionPage,
      reverseDuration: AppTheme.motionPageReverse,
      value: _terminalVisible ? 1 : 0,
    );
    unawaited(
      AnalyticsService.instance.screen(
        _terminalVisible ? AnalyticsScreen.terminal : _screenNames.first,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncNotificationAnchor();
    });
    tabBarPositionSetting.addListener(_onTabBarPositionChanged);
  }

  void _onTabBarPositionChanged() {
    if (mounted) _syncNotificationAnchor();
  }

  @override
  void dispose() {
    tabBarPositionSetting.removeListener(_onTabBarPositionChanged);
    _terminalMotion.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index != _currentIndex) {
      unawaited(AnalyticsService.instance.screen(_screenNames[index]));
    }
    setState(() => _currentIndex = index);
  }

  /// The tab the terminal was covering comes back into view when it goes
  /// away, which is a screen view like any other.
  void _reportCurrentTab() {
    unawaited(AnalyticsService.instance.screen(_screenNames[_currentIndex]));
  }

  void _hideTerminal() {
    _terminalKey.currentState?.blurAll();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _terminalVisible = false;
    });
    _animateTerminal(visible: false);
    _syncNotificationAnchor();
    _reportCurrentTab();
    ref.read(terminalOverlayProvider.notifier).hide();
  }

  void _onTerminalClose() {
    setState(() => _terminalVisible = false);
    _animateTerminal(visible: false);
    final generation = ++_closeGeneration;
    void drop() {
      if (!mounted || generation != _closeGeneration || _terminalVisible) {
        return;
      }
      setState(() {
        _terminalSession = null;
        _terminalKey = GlobalKey<TerminalScreenState>();
      });
    }

    if (_terminalMotion.isDismissed) {
      drop();
    } else {
      _terminalMotion.reverse().whenCompleteOrCancel(drop);
    }
    _syncNotificationAnchor();
    _reportCurrentTab();
    ref.read(terminalOverlayProvider.notifier).hide();
  }

  /// Toasts hang off the bottom of whichever app bar is on top, and the
  /// terminal's tab strip is taller than a standard one - except in
  /// landscape, where the strip has moved into a side rail, or with the
  /// strip moved to the bottom, which leaves nothing up top to hang off. Never called from build - the overlay listening on
  /// it is outside this element tree and would be marked dirty mid-build.
  void _syncNotificationAnchor() {
    appNotificationAnchor.value = _terminalVisible
        ? (isWideLayout(context) ||
                  tabBarPositionSetting.value == TabBarPosition.bottom
              ? 0
              : terminalTabBarHeight(context))
        : kToolbarHeight;
  }

  List<_NavItemData> _navItems(Translations t) => [
    _NavItemData(
      label: t.nav.home,
      icon: PhosphorIconsRegular.terminal,
      selectedIcon: PhosphorIconsFill.terminal,
    ),
    _NavItemData(
      label: t.nav.snippets,
      icon: PhosphorIconsRegular.codeBlock,
      selectedIcon: PhosphorIconsFill.codeBlock,
    ),
    _NavItemData(
      label: t.nav.keys,
      icon: PhosphorIconsRegular.key,
      selectedIcon: PhosphorIconsFill.key,
    ),
    _NavItemData(
      label: t.nav.settings,
      icon: PhosphorIconsRegular.gearSix,
      selectedIcon: PhosphorIconsFill.gearSix,
    ),
  ];

  Widget _buildMobileScaffold(Translations t) {
    return Scaffold(
      body: _AnimatedNavBody(currentIndex: _currentIndex, children: _screens),
      bottomNavigationBar: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) {
          final manager = _manager;
          final dockSession = manager.lastSession;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_terminalVisible && dockSession != null)
                _SessionDock(
                  session: dockSession,
                  sessionCount: manager.restoreStripSize(dockSession.id),
                  onTap: () => ref
                      .read(terminalOverlayProvider.notifier)
                      .show(dockSession.id, dockSession.profile),
                ),
              _BottomNavBar(
                key: const ValueKey('bottomNavBar'),
                currentIndex: _currentIndex,
                onSelected: _selectTab,
                items: _navItems(t),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The rail already covers the left edge, cutout and all, but the screens
  /// beside it would still read the window's own left inset off
  /// `MediaQuery` - `Scaffold` passes left/right padding straight through to
  /// its body, and every `AppBar` re-applies it via its own `SafeArea`. Left
  /// unremoved, each screen would indent itself a second time for a cutout
  /// it is nowhere near, so its content would sit further from the rail than
  /// from the right edge.
  Widget _buildDesktopScaffold(Translations t) {
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) {
              final manager = _manager;
              final dockSession = manager.lastSession;
              return ValueListenableBuilder<bool>(
                valueListenable: sidebarCollapsedSetting,
                builder: (context, collapsed, _) => _Sidebar(
                  key: const ValueKey('sidebarNav'),
                  currentIndex: _currentIndex,
                  onSelected: _selectTab,
                  items: _navItems(t),
                  collapsed: collapsed,
                  dockSession: !_terminalVisible ? dockSession : null,
                  dockSessionCount: dockSession != null
                      ? manager.restoreStripSize(dockSession.id)
                      : 0,
                  onDockTap: dockSession == null
                      ? null
                      : () => ref
                            .read(terminalOverlayProvider.notifier)
                            .show(dockSession.id, dockSession.profile),
                ),
              );
            },
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: _AnimatedNavBody(
                currentIndex: _currentIndex,
                children: _screens,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    ref.listen(terminalOverlayProvider, (prev, next) {
      if (next != null) {
        final hasLiveScreen = _terminalKey.currentState != null;
        _closeGeneration++;
        setState(() {
          _terminalSession = (next.$1, next.$2);
          _siblingScope = next.$3;
          _terminalVisible = true;
          if (!hasLiveScreen) {
            _terminalKey = GlobalKey<TerminalScreenState>();
          }
        });
        if (hasLiveScreen) {
          _terminalKey.currentState?.openSession(next.$1, next.$2);
        }
        _animateTerminalAfterBuild();
        _syncNotificationAnchor();
        unawaited(AnalyticsService.instance.screen(AnalyticsScreen.terminal));
      }
    });

    return PopScope(
      canPop: !_terminalVisible && _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_terminalVisible) {
          final handled = _terminalKey.currentState?.handleBack() ?? false;
          if (handled) return;
          _hideTerminal();
          return;
        }
        if (_currentIndex != 0) {
          _selectTab(0);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.colors.backgroundPrimary),
          FadeOverColorTransition(
            opacity: _backgroundFade,
            color: context.colors.backgroundPrimary,
            child: ScaleTransition(
              scale: _backgroundScale,
              child: RepaintBoundary(
                child: isWideLayout(context)
                    ? _buildDesktopScaffold(t)
                    : _buildMobileScaffold(t),
              ),
            ),
          ),
          if (_terminalSession != null)
            IgnorePointer(
              ignoring: !_terminalVisible,
              child: FadeOverColorTransition(
                opacity: _terminalFade,
                color: context.colors.backgroundPrimary,
                child: ScaleTransition(
                  scale: _terminalScale,
                  child: RepaintBoundary(
                    child: TerminalSchemeTheme(
                      child: TerminalScreen(
                        key: _terminalKey,
                        initialSessionId: _terminalSession!.$1,
                        initialProfile: _terminalSession!.$2,
                        siblingScope: _siblingScope,
                        onClose: _onTerminalClose,
                        onHide: _hideTerminal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionDock extends ConsumerWidget {
  const _SessionDock({
    required this.session,
    required this.sessionCount,
    required this.onTap,
    this.collapsed = false,
  });

  final ActiveSessionView session;
  final int sessionCount;
  final VoidCallback onTap;

  /// Icons-only, for a collapsed rail. The bottom-nav dock is never
  /// collapsed, so this only ever comes from [_Sidebar].
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final shouldRestore = session.dropped;
    final anonymize = ref.watch(anonymizeProvider);
    final displayName = anonymize
        ? IdentityAnonymizer.name(session.profile.id)
        : session.profile.name;
    final displayUsername = anonymize
        ? IdentityAnonymizer.username(session.profile.id)
        : session.profile.username;
    final displayHost = anonymize
        ? IdentityAnonymizer.host(session.profile.id)
        : session.profile.host;
    return Tooltip(
      message: shouldRestore
          ? t.session.attach
          : t.profiles.returnToSession(name: displayName),
      child: Material(
        color: context.colors.surfaceElevated,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            height: 58,
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? AppTheme.space8 : AppTheme.space14,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.surfaceBorder),
              ),
            ),
            child: collapsed
                ? Center(
                    child: ProfileAvatar(
                      iconName: session.profile.iconName,
                      colorHex: session.profile.colorHex,
                      isActive: !shouldRestore,
                      size: 34,
                    ),
                  )
                : Row(
                    children: [
                      ProfileAvatar(
                        iconName: session.profile.iconName,
                        colorHex: session.profile.colorHex,
                        isActive: !shouldRestore,
                        size: 34,
                      ),
                      const SizedBox(width: AppTheme.space10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: AppTheme.space2),
                            Text(
                              shouldRestore
                                  ? t.session.restoreDock(
                                      target: '$displayUsername@$displayHost',
                                    )
                                  : '$displayUsername@$displayHost',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.colors.uiSmall.copyWith(
                                color: shouldRestore
                                    ? context.colors.warning
                                    : context.colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (sessionCount > 1) ...[
                        AppBadge.count(sessionCount),
                        const SizedBox(width: AppTheme.space10),
                      ],
                      Icon(
                        shouldRestore
                            ? PhosphorIconsFill.arrowClockwise
                            : PhosphorIconsFill.terminalWindow,
                        size: AppTheme.icon18,
                        color: shouldRestore
                            ? context.colors.warning
                            : context.colors.textSecondary,
                      ),
                      const SizedBox(width: AppTheme.space4),
                      Icon(
                        PhosphorIconsFill.caretRight,
                        size: AppTheme.icon14,
                        color: context.colors.textTertiary,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedNavBody extends StatelessWidget {
  const _AnimatedNavBody({required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != currentIndex,
            child: AnimatedOpacity(
              opacity: i == currentIndex ? 1 : 0,
              duration: AppTheme.motionSlow,
              curve: Curves.easeOutCubic,
              child: children[i],
            ),
          ),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<_NavItemData> items;

  @override
  Widget build(BuildContext context) {
    const itemGap = AppTheme.space8;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.backgroundPrimary,
        border: Border(top: BorderSide(color: context.colors.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space10,
            AppTheme.space8,
            AppTheme.space10,
            AppTheme.space10,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalGap = itemGap * (items.length - 1);
              final itemWidth =
                  (constraints.maxWidth - totalGap) / items.length;

              return SizedBox(
                height: 62,
                child: Row(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: itemGap),
                      SizedBox(
                        width: itemWidth,
                        child: _BottomNavItem(
                          data: items[i],
                          selected: currentIndex == i,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onSelected(i);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.backgroundPrimary.invisible,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        splashFactory: NoSplash.splashFactory,
        splashColor: context.colors.primary.invisible,
        highlightColor: context.colors.primary.invisible,
        hoverColor: context.colors.primary.invisible,
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          curve: AppTheme.interactiveCurve,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.primaryHighlight
                : context.colors.primaryHighlight.invisible,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? data.selectedIcon : data.icon,
                size: AppTheme.icon22,
                color: selected
                    ? context.colors.primary
                    : context.colors.textSecondary,
              ),
              const SizedBox(height: AppTheme.space4),
              Text(
                data.label,
                style: context.colors.uiSmall.copyWith(
                  fontSize: AppTheme.font11,
                  color: selected
                      ? context.colors.primary
                      : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Replacement for the bottom nav bar on desktop and tablet landscape - a
/// rail down the left edge, since a surface this wide has room to spare down
/// the side instead.
///
/// The hamburger at the top collapses it to [kNavRailCollapsedWidth], where
/// the labels drop and only the icons remain - a wide window can afford 240pt
/// of chrome, a phone held sideways cannot.
///
/// A landscape cutout is inset the rail sits behind, not room taken out of
/// it: the rail grows by it and the `SafeArea` below hands its contents the
/// full width back, or a collapsed rail would be 64pt with a 48pt cutout
/// eaten out of it, leaving nothing for the icons to be drawn in. The width
/// change is animated by laying out the contents at the width being
/// animated to and clipping them, not by laying out at each intermediate
/// width - a 240pt label has no legible form at 100pt, so reflowing it frame
/// by frame would only produce an overflow stripe on its way out.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    required this.collapsed,
    required this.dockSession,
    required this.dockSessionCount,
    required this.onDockTap,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<_NavItemData> items;
  final bool collapsed;
  final ActiveSessionView? dockSession;
  final int dockSessionCount;
  final VoidCallback? onDockTap;

  @override
  Widget build(BuildContext context) {
    final safeInset = MediaQuery.paddingOf(context).left;
    final width = navRailWidth(collapsed) + safeInset;
    final itemInset = collapsed ? AppTheme.space8 : AppTheme.space12;

    return AnimatedContainer(
      duration: AppTheme.motionSlow,
      curve: AppTheme.interactiveCurve,
      width: width,
      decoration: BoxDecoration(
        color: context.colors.backgroundPrimary,
        border: Border(right: BorderSide(color: context.colors.surfaceBorder)),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: SafeArea(
            right: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space12,
                    AppTheme.space12,
                    AppTheme.space12,
                    AppTheme.space4,
                  ),
                  child: Align(
                    alignment: collapsed
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: NavRailToggleButton(collapsed: collapsed),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      itemInset,
                      AppTheme.space4,
                      itemInset,
                      AppTheme.space12,
                    ),
                    children: [
                      for (int i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTheme.space4,
                          ),
                          child: _SidebarNavItem(
                            data: items[i],
                            selected: currentIndex == i,
                            collapsed: collapsed,
                            onTap: () => onSelected(i),
                          ),
                        ),
                    ],
                  ),
                ),
                if (dockSession != null && onDockTap != null)
                  _SessionDock(
                    session: dockSession!,
                    sessionCount: dockSessionCount,
                    collapsed: collapsed,
                    onTap: onDockTap!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed, the icon is all there is to go on, so the label it replaced
/// stays reachable as a tooltip instead.
class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.data,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.colors.primary
        : context.colors.textSecondary;
    final icon = Icon(
      selected ? data.selectedIcon : data.icon,
      size: AppTheme.icon20,
      color: foreground,
    );

    final Widget button = Material(
      color: context.colors.backgroundPrimary.invisible,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          curve: AppTheme.interactiveCurve,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : AppTheme.space14,
            vertical: AppTheme.space10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.primaryHighlight
                : context.colors.primaryHighlight.invisible,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: collapsed
              ? Center(child: icon)
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: AppTheme.space12),
                    Text(
                      data.label,
                      style: context.colors.uiStyle.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: data.label, child: button) : button;
  }
}

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
import '../widgets/terminal/terminal_scheme_theme.dart';
import '../widgets/ui/app_notifications.dart';
import '../widgets/ui/nav_rail.dart';
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

  /// Brings the terminal up over the tabs and takes it back down: it rises a
  /// little as it fades in while the screen behind it sinks back, and leaves
  /// the same way, quicker. A closed strip is only dropped once it has gone,
  /// so closing animates too.
  late final AnimationController _terminalMotion;
  late final Animation<double> _terminalCurve = CurvedAnimation(
    parent: _terminalMotion,
    curve: AppTheme.interactiveCurve,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _terminalFade = CurvedAnimation(
    parent: _terminalMotion,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
    reverseCurve: const Interval(0.2, 1, curve: Curves.easeIn),
  );
  late final Animation<Offset> _terminalSlide = Tween(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(_terminalCurve);
  late final Animation<double> _backgroundScale = Tween(
    begin: 1.0,
    end: 0.96,
  ).animate(_terminalCurve);

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
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
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
        _animateTerminal(visible: true);
        _syncNotificationAnchor();
        unawaited(AnalyticsService.instance.screen(AnalyticsScreen.terminal));
        if (hasLiveScreen) {
          _terminalKey.currentState?.openSession(next.$1, next.$2);
        }
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
          ScaleTransition(
            scale: _backgroundScale,
            child: isWideLayout(context)
                ? _buildDesktopScaffold(t)
                : _buildMobileScaffold(t),
          ),
          if (_terminalSession != null)
            IgnorePointer(
              ignoring: !_terminalVisible,
              child: FadeTransition(
                opacity: _terminalFade,
                child: SlideTransition(
                  position: _terminalSlide,
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
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 14),
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
                      const SizedBox(width: 11),
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
                            const SizedBox(height: 2),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceCard,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXs,
                            ),
                            border: Border.all(
                              color: context.colors.surfaceBorder,
                            ),
                          ),
                          child: Text(
                            '$sessionCount',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Icon(
                        shouldRestore
                            ? PhosphorIconsFill.arrowClockwise
                            : PhosphorIconsFill.terminalWindow,
                        size: 19,
                        color: shouldRestore
                            ? context.colors.warning
                            : context.colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        PhosphorIconsFill.caretRight,
                        size: 15,
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
    const itemGap = 8.0;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.backgroundPrimary,
        border: Border(top: BorderSide(color: context.colors.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                size: 22,
                color: selected
                    ? context.colors.primary
                    : context.colors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                data.label,
                style: context.colors.uiSmall.copyWith(
                  fontSize: 11,
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
    final itemInset = collapsed ? 8.0 : 12.0;

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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Align(
                    alignment: collapsed
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: NavRailToggleButton(collapsed: collapsed),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(itemInset, 4, itemInset, 12),
                    children: [
                      for (int i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
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
      size: 20,
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
            horizontal: collapsed ? 0 : 14,
            vertical: 11,
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
                    const SizedBox(width: 12),
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

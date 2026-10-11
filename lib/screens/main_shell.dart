import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../i18n/strings.g.dart';
import '../models/active_session.dart';
import '../models/session_tab.dart';
import '../models/ssh_profile.dart';
import '../providers/anonymize_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/ssh_session_manager_provider.dart';
import '../providers/terminal_overlay_provider.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app/app_commands.dart';
import '../services/app/identity_anonymizer.dart';
import '../services/app/manual_urls.dart';
import '../services/platform/desktop_window.dart';
import '../services/settings/sidebar_settings.dart';
import '../services/settings/tab_bar_settings.dart';
import '../services/settings/terminal_settings.dart';
import '../services/ssh/ssh_session_manager.dart';
import '../theme/theme.dart';
import '../utils/platform_info.dart';
import '../widgets/profiles/profile_avatar.dart';
import '../widgets/profiles/profile_form_dialog.dart';
import '../widgets/terminal/add_session_sheet.dart';
import '../widgets/terminal/session_tab_pill.dart';
import '../widgets/terminal/terminal_scheme_theme.dart';
import '../widgets/ui/app_notifications.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/manual_link.dart';
import '../widgets/ui/nav_rail.dart';
import '../widgets/ui/section_navigator.dart';
import '../widgets/window/shortcuts_dialog.dart';
import 'home_screen.dart';
import 'keys/key_manager_screen.dart';
import 'search/global_search_launcher.dart';
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
class _MainShellState extends ConsumerState<MainShell> {
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

  @override
  void initState() {
    super.initState();
    final restored = _manager.lastActiveSession;
    if (restored != null) {
      _terminalSession = (restored.id, restored.profile);
      _terminalVisible = true;
    }
    unawaited(
      AnalyticsService.instance.screen(
        _terminalVisible ? AnalyticsScreen.terminal : _screenNames.first,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncNotificationAnchor();
      _syncWindowTitle();
    });
    tabBarPositionSetting.addListener(_onTabBarPositionChanged);
    _registerCommands();
  }

  final _unregisterCommands = <VoidCallback>[];

  /// What the shell answers of the desktop's shortcuts and menus: going
  /// places, and - while a session is on screen - the terminal's own, handed
  /// to the strip.
  ///
  /// A new session with no strip on screen opens the same picker the
  /// terminal opens, so a session is asked for in one place wherever it is
  /// asked from. The zoom commands work with or without a session on screen,
  /// since the terminal's text size is one preference wherever it is changed
  /// from.
  void _registerCommands() {
    void on(AppCommand command, bool Function(int? argument) handler) =>
        _unregisterCommands.add(
          AppCommands.instance.register(command, handler),
        );

    TerminalScreenState? liveTerminal() =>
        _terminalVisible ? _terminalKey.currentState : null;

    bool terminal(void Function(TerminalScreenState state) action) {
      final state = liveTerminal();
      if (state == null) return false;
      action(state);
      return true;
    }

    on(AppCommand.globalSearch, (_) {
      final ctx = _commandContext();
      if (ctx == null) return false;
      unawaited(openGlobalSearch(ctx, heroTag: 'globalSearch-shortcut'));
      return true;
    });
    on(AppCommand.newMachine, (_) {
      final ctx = _commandContext();
      if (ctx == null) return false;
      unawaited(
        pushAppForm<void>(ctx, builder: (_) => const ProfileFormDialog()),
      );
      return true;
    });
    on(AppCommand.openSettings, (_) {
      _selectSection(3);
      return true;
    });
    on(AppCommand.toggleSidebar, (_) {
      unawaited(sidebarCollapsedSetting.set(!sidebarCollapsedSetting.value));
      return true;
    });
    on(AppCommand.showShortcuts, (_) {
      final ctx = _commandContext();
      if (ctx == null) return false;
      unawaited(showShortcutsDialog(ctx));
      return true;
    });
    on(AppCommand.openManual, (_) {
      final ctx = _commandContext();
      if (ctx == null) return false;
      unawaited(openManual(ctx, ManualPage.home));
      return true;
    });
    on(AppCommand.newSession, (_) {
      final state = liveTerminal();
      if (state != null) {
        state.newSession();
        return true;
      }
      final ctx = _commandContext();
      if (ctx == null) return false;
      final overlay = ref.read(terminalOverlayProvider.notifier);
      unawaited(
        showAppSheet<void>(
          context: ctx,
          handle: false,
          builder: (sheetCtx) => AddSessionSheetContent(
            profiles: ref.read(profilesProvider),
            resumableFor: _manager.resumableTabsForProfile,
            onSelect: (profile) {
              Navigator.of(sheetCtx).pop();
              overlay.show(
                const Uuid().v4(),
                profile,
                scope: SiblingScope.none,
              );
            },
            onAttach: (tabId, profile) {
              Navigator.of(sheetCtx).pop();
              overlay.show(tabId, profile, scope: SiblingScope.none);
            },
          ),
        ),
      );
      return true;
    });
    on(AppCommand.closeTab, (_) => terminal((s) => s.closeActiveTab()));
    on(AppCommand.nextTab, (_) => terminal((s) => s.selectRelativeTab(1)));
    on(AppCommand.previousTab, (_) => terminal((s) => s.selectRelativeTab(-1)));
    on(
      AppCommand.selectTab,
      (index) => terminal((s) => s.selectTabAt(index ?? 0)),
    );
    on(
      AppCommand.findInTerminal,
      (_) => terminal((s) => s.findInActiveSession()),
    );
    on(
      AppCommand.uploadFile,
      (_) => terminal((s) => s.uploadToActiveSession()),
    );
    on(AppCommand.zoomIn, (_) => _zoomTerminal(1));
    on(AppCommand.zoomOut, (_) => _zoomTerminal(-1));
    on(AppCommand.zoomReset, (_) {
      unawaited(terminalSettings.fontSize.set(kTerminalDefaultFontSize));
      return true;
    });
  }

  bool _zoomTerminal(double delta) {
    final size = terminalSettings.fontSize.value + delta;
    unawaited(
      terminalSettings.fontSize.set(
        size.clamp(kTerminalMinFontSize, kTerminalMaxFontSize).toDouble(),
      ),
    );
    return true;
  }

  /// Where a command opens what it opens: the section on screen, so a page
  /// lands beside the sidebar, or the app's own context otherwise.
  BuildContext? _commandContext() {
    if (!mounted) return null;
    if (!_terminalVisible) {
      final section = _sectionKeys[_currentIndex].currentContext;
      if (section != null) return section;
    }
    return context;
  }

  void _onTabBarPositionChanged() {
    if (mounted) _syncNotificationAnchor();
  }

  @override
  void dispose() {
    for (final unregister in _unregisterCommands) {
      unregister();
    }
    tabBarPositionSetting.removeListener(_onTabBarPositionChanged);
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

  /// The window's own title, which the taskbar and the window switcher show:
  /// the machine on screen, or just the app.
  void _syncWindowTitle() {
    terminalOnScreen.value = _terminalVisible;
    final session = _terminalVisible ? _terminalSession : null;
    if (session == null) {
      unawaited(DesktopWindow.instance.setTitle('Termphin'));
      return;
    }
    final name = ref.read(anonymizeProvider)
        ? IdentityAnonymizer.name(session.$2.id)
        : session.$2.name;
    unawaited(DesktopWindow.instance.setTitle('$name - Termphin'));
  }

  void _hideTerminal() {
    _terminalKey.currentState?.blurAll();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _terminalVisible = false;
    });
    _syncNotificationAnchor();
    _syncWindowTitle();
    _reportCurrentTab();
    ref.read(terminalOverlayProvider.notifier).hide();
  }

  void _onTerminalClose() {
    setState(() {
      _terminalVisible = false;
      _terminalSession = null;
      _terminalKey = GlobalKey<TerminalScreenState>();
    });
    _syncNotificationAnchor();
    _syncWindowTitle();
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

  List<ShellNavItem> _navItems(Translations t) => [
    ShellNavItem(
      label: t.nav.home,
      icon: PhosphorIconsRegular.terminal,
      selectedIcon: PhosphorIconsFill.terminal,
    ),
    ShellNavItem(
      label: t.nav.snippets,
      icon: PhosphorIconsRegular.codeBlock,
      selectedIcon: PhosphorIconsFill.codeBlock,
    ),
    ShellNavItem(
      label: t.nav.keys,
      icon: PhosphorIconsRegular.key,
      selectedIcon: PhosphorIconsFill.key,
    ),
    ShellNavItem(
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

  /// One navigator per section on a desktop, so a page opened from a list
  /// or a settings row stays beside the sidebar. Keyed so a click on the
  /// section already selected can take it back to its root.
  final _sectionKeys = List.generate(
    4,
    (_) => GlobalKey<SectionNavigatorState>(),
  );

  void _selectSection(int index) {
    if (index == _currentIndex && !_terminalVisible) {
      _sectionKeys[index].currentState?.popToRoot();
    }
    if (_terminalVisible) _hideTerminal();
    _selectTab(index);
  }

  List<Widget> _sectionBodies(Translations t) {
    if (!isDesktopPlatform) return _screens;
    final items = _navItems(t);
    return [
      for (var i = 0; i < _screens.length; i++)
        SectionNavigator(
          key: _sectionKeys[i],
          label: items[i].label,
          active: i == _currentIndex && !_terminalVisible,
          child: _screens[i],
        ),
    ];
  }

  /// The rail already covers the left edge, cutout and all, but the screens
  /// beside it would still read the window's own left inset off
  /// `MediaQuery` - `Scaffold` passes left/right padding straight through to
  /// its body, and every `AppBar` re-applies it via its own `SafeArea`. Left
  /// unremoved, each screen would indent itself a second time for a cutout
  /// it is nowhere near, so its content would sit further from the rail than
  /// from the right edge.
  Widget _buildDesktopScaffold(Translations t) {
    final desktop = isDesktopPlatform;
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) {
              final manager = _manager;
              final dockSession = desktop ? null : manager.lastSession;
              return ValueListenableBuilder<bool>(
                valueListenable: sidebarCollapsedSetting,
                builder: (context, collapsed, _) => _Sidebar(
                  key: const ValueKey('sidebarNav'),
                  currentIndex: _currentIndex,
                  onSelected: _selectSection,
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
                  sessions: desktop ? manager.restorableTabs : const [],
                  onSessionTap: (session) => ref
                      .read(terminalOverlayProvider.notifier)
                      .show(session.id, session.profile),
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
                children: _sectionBodies(t),
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
        setState(() {
          _terminalSession = (next.$1, next.$2);
          _siblingScope = next.$3;
          _terminalVisible = true;
          if (!hasLiveScreen) {
            _terminalKey = GlobalKey<TerminalScreenState>();
          }
        });
        _syncNotificationAnchor();
        _syncWindowTitle();
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
          isWideLayout(context)
              ? _buildDesktopScaffold(t)
              : _buildMobileScaffold(t),
          if (_terminalSession != null)
            IgnorePointer(
              ignoring: !_terminalVisible,
              child: AnimatedOpacity(
                opacity: _terminalVisible ? 1.0 : 0.0,
                duration: AppTheme.motionSlow,
                curve: Curves.easeOutCubic,
                child: TerminalSchemeTheme(
                  child: TerminalScreen(
                    key: _terminalKey,
                    initialSessionId: _terminalSession!.$1,
                    initialProfile: _terminalSession!.$2,
                    siblingScope: _siblingScope,
                    onClose: _onTerminalClose,
                    onHide: _hideTerminal,
                    navItems: isDesktopPlatform ? _navItems(t) : const [],
                    onNavigate: _selectSection,
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
  final List<ShellNavItem> items;

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

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final ShellNavItem data;
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
/// of chrome, a phone held sideways cannot, so there it stays collapsed and
/// the hamburger goes.
///
/// On a desktop the open sessions are listed under the destinations, the way
/// the terminal's own rail lists them under the same destinations: the two
/// are one strip, and the terminal is a place in it rather than a screen
/// stacked over it. A phone keeps the single dock row at the bottom.
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
    this.sessions = const [],
    this.onSessionTap,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<ShellNavItem> items;
  final bool collapsed;
  final ActiveSessionView? dockSession;
  final int dockSessionCount;
  final VoidCallback? onDockTap;

  /// What the strip would hold: live tabs, and dropped ones it will pick
  /// back up. One detached on purpose is not a session on screen - it waits
  /// in the new-session sheet, as on a phone.
  final List<ActiveSessionView> sessions;
  final ValueChanged<ActiveSessionView>? onSessionTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
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
                          child: SidebarNavItem(
                            data: items[i],
                            selected: currentIndex == i,
                            collapsed: collapsed,
                            onTap: () => onSelected(i),
                          ),
                        ),
                      if (sessions.isNotEmpty && onSessionTap != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: SidebarSectionLabel(
                                t.nav.sessions,
                                collapsed: collapsed,
                              ),
                            ),
                            if (!collapsed)
                              StripActionButton(
                                tooltip: t.terminal.selectDevice,
                                icon: PhosphorIconsRegular.plus,
                                onTap: () => AppCommands.instance.run(
                                  AppCommand.newSession,
                                ),
                              ),
                          ],
                        ),
                        for (final session in sessions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: _SidebarSessionRow(
                              session: session,
                              collapsed: collapsed,
                              onTap: () => onSessionTap!(session),
                            ),
                          ),
                      ],
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

/// An open session in the desktop sidebar: the same pill the terminal's strip
/// draws, so a session looks alike whether or not it is on screen. A click
/// brings the terminal back on it.
///
/// Its status is read off the session rather than its connection provider:
/// that is keyed by the profile object too, and watching it from here could
/// stand up a second notifier for a session the strip already owns.
class _SidebarSessionRow extends ConsumerWidget {
  const _SidebarSessionRow({
    required this.session,
    required this.collapsed,
    required this.onTap,
  });

  final ActiveSessionView session;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anonymize = ref.watch(anonymizeProvider);
    final profile = session.profile;
    final name = anonymize ? IdentityAnonymizer.name(profile.id) : profile.name;
    final sessionName = session.multiplexer.isPersistent
        ? ref.read(sshSessionManagerProvider).muxNameFor(session.id)
        : null;
    final status = session.connecting
        ? context.colors.warning
        : session.dropped
        ? Theme.of(context).dividerColor
        : context.colors.success;
    final pill = SessionTabPill(
      key: ValueKey('sidebarSession-${session.id}'),
      sessionId: session.id,
      profile: profile,
      statusColor: status,
      sessionName: sessionName,
      displayName: name,
      collapsed: collapsed,
      onTap: onTap,
    );
    if (!collapsed) return pill;
    return Tooltip(
      message: sessionName != null
          ? '${SessionTab.displayName(sessionName)} - $name'
          : name,
      child: pill,
    );
  }
}

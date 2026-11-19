import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
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
import '../services/settings/terminal_settings.dart';
import '../services/ssh/ssh_session_manager.dart';
import '../theme/theme.dart';
import '../utils/platform_info.dart';
import '../widgets/profiles/profile_avatar.dart';
import '../widgets/profiles/profile_form_dialog.dart';
import '../widgets/settings/analytics_ask_card.dart';
import '../widgets/settings/manual_link.dart';
import '../widgets/shell/nav_rail.dart';
import '../widgets/terminal/add_session_sheet.dart';
import '../widgets/terminal/notice_dot.dart';
import '../widgets/terminal/session_tab_pill.dart';
import '../widgets/terminal/terminal_scheme_theme.dart';
import '../widgets/ui/app_badge.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/fade_over_color.dart';
import '../widgets/ui/large_title_scaffold.dart';
import '../widgets/ui/section_navigator.dart';
import '../widgets/window/app_menu.dart';
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
      if (!mounted) return;
      _syncWindowTitle();
      _syncTerminalOnScreen();
    });
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
    on(AppCommand.toggleFiles, (_) => terminal((s) => s.toggleActiveFiles()));
    on(AppCommand.endSession, (_) => terminal((s) => s.endActiveSession()));
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

  @override
  void dispose() {
    for (final unregister in _unregisterCommands) {
      unregister();
    }
    _terminalMotion.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index != 0) AnalyticsService.instance.dismissAsk();
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
    _animateTerminal(visible: false);
    _syncWindowTitle();
    _syncTerminalOnScreen();
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
    _syncWindowTitle();
    _syncTerminalOnScreen();
    _reportCurrentTab();
    ref.read(terminalOverlayProvider.notifier).hide();
  }

  /// Tells the session manager whether the terminal is what is on screen,
  /// which is what decides if a program's notification is news.
  void _syncTerminalOnScreen() {
    _manager.terminalOnScreen = _terminalVisible;
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
      extendBody: true,
      body: Stack(
        children: [
          _AnimatedNavBody(currentIndex: _currentIndex, children: _screens),
          _AnalyticsAskOverlay(
            visible: _currentIndex == 0 && !_terminalVisible,
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) {
          final manager = _manager;
          final dockSession = manager.lastSession;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BottomNavBar(
                key: const ValueKey('bottomNavBar'),
                currentIndex: _currentIndex,
                onSelected: _selectTab,
                items: _navItems(t),
                dock: !_terminalVisible && dockSession != null
                    ? _SessionDock(
                        session: dockSession,
                        sessionCount: manager.restoreStripSize(dockSession.id),
                        embedded: true,
                        onTap: () => ref
                            .read(terminalOverlayProvider.notifier)
                            .show(dockSession.id, dockSession.profile),
                      )
                    : null,
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
              return SidebarBuilder(
                builder: (context, collapsed) => _Sidebar(
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
              child: Stack(
                children: [
                  _AnimatedNavBody(
                    currentIndex: _currentIndex,
                    covered: desktop && _terminalVisible,
                    children: _sectionBodies(t),
                  ),
                  _AnalyticsAskOverlay(
                    visible: _currentIndex == 0 && !_terminalVisible,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the title bar's menus hold for where the user is: the session's
  /// while one is on screen, the list's on a list. A section with nothing
  /// of its own to offer adds no menu rather than an empty one.
  List<AppMenu> _contextMenus(Translations t) {
    if (_terminalVisible) {
      return _terminalKey.currentState?.menus(t) ?? const [];
    }
    if (_currentIndex != 0) return const [];
    return [
      AppMenu(t.window.menuMachines, [
        [
          AppMenuItem.command(
            t,
            AppCommand.newMachine,
            icon: PhosphorIconsRegular.plus,
          ),
          AppMenuItem.command(
            t,
            AppCommand.newSession,
            icon: PhosphorIconsRegular.terminalWindow,
          ),
        ],
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    ref.listen(terminalOverlayProvider, (prev, next) {
      if (next != null) {
        final hasLiveScreen = _terminalKey.currentState != null;
        _closeGeneration++;
        AnalyticsService.instance.dismissAsk();
        setState(() {
          _terminalSession = (next.$1, next.$2);
          _siblingScope = next.$3;
          _terminalVisible = true;
          if (!hasLiveScreen) {
            _terminalKey = GlobalKey<TerminalScreenState>();
          }
        });
        _syncWindowTitle();
        if (hasLiveScreen) {
          _terminalKey.currentState?.openSession(next.$1, next.$2);
        }
        _animateTerminalAfterBuild();
        _syncTerminalOnScreen();
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
      child: ContextMenuScope(
        active: isDesktopPlatform,
        menus: _contextMenus,
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
                          navItems: isDesktopPlatform ? _navItems(t) : const [],
                          onNavigate: _selectSection,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
    this.embedded = false,
  });

  final ActiveSessionView session;
  final int sessionCount;
  final VoidCallback onTap;

  /// Icons-only, for a collapsed rail. The bottom-nav dock is never
  /// collapsed, so this only ever comes from [_Sidebar].
  final bool collapsed;

  /// Inside the bottom bar's panel, which draws the ground and the edges:
  /// no fill and no rule of its own.
  final bool embedded;

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
    final manager = ref.read(sshSessionManagerProvider);
    final avatar = ListenableBuilder(
      listenable: manager,
      builder: (context, _) => NoticeDot(
        visible: manager.hasAnyUnreadNotice,
        ground: embedded
            ? context.colors.surfaceCard
            : context.colors.surfaceElevated,
        child: ProfileAvatar(
          iconName: session.profile.iconName,
          colorHex: session.profile.colorHex,
          isActive: !shouldRestore,
          size: 34,
        ),
      ),
    );
    return Tooltip(
      message: shouldRestore
          ? t.session.attach
          : t.profiles.returnToSession(name: displayName),
      child: Material(
        color: embedded
            ? context.colors.surfaceCard.invisible
            : context.colors.surfaceElevated,
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
              border: embedded
                  ? null
                  : Border(
                      top: BorderSide(color: context.colors.surfaceBorder),
                    ),
            ),
            child: collapsed
                ? Center(child: avatar)
                : Row(
                    children: [
                      avatar,
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
                        PhosphorIconsRegular.caretRight,
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
  const _AnimatedNavBody({
    required this.currentIndex,
    required this.children,
    this.covered = false,
  });

  final int currentIndex;
  final List<Widget> children;

  /// Whether something is drawn over every section - a session on a
  /// desktop - so that none of them is the page in front.
  final bool covered;

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
              duration: isDesktopPlatform ? Duration.zero : AppTheme.motionSlow,
              curve: Curves.easeOutCubic,
              child: ExcludeFocus(
                excluding: i != currentIndex || covered,
                child: TickerMode(
                  enabled: i == currentIndex && !covered,
                  child: children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The tab bar on a phone: a capsule floating clear of the screen edges,
/// with the open tab as a lighter segment that slides to whichever tab is
/// picked - the same recessed-track-and-thumb look as the app's segmented
/// switches, so the two read as one family.
///
/// It sits in the scaffold's bottom slot rather than over the content, so no
/// list has to leave room under its last row for it.
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.dock,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<ShellNavItem> items;

  /// The session dock, carried inside the bar: the capsule grows into one
  /// rounded panel with the way back to the session on top of the tabs, so
  /// the foot of the screen is one thing rather than a strip and a pill.
  final Widget? dock;

  static const _inset = AppTheme.space4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dock = this.dock;
    final radius = dock == null ? AppTheme.radiusPill : AppTheme.radiusLg;
    final tabs = SizedBox(
      height: AppTheme.bottomBarHeight - _inset * 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppTheme.interactiveDuration,
                curve: AppTheme.interactiveCurve,
                left: itemWidth * currentIndex,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceOffset2,
                    borderRadius: BorderRadius.circular(
                      dock == null ? AppTheme.radiusPill : AppTheme.radiusMd,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < items.length; i++)
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
              ),
            ],
          );
        },
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg + AppTheme.space16),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: AppTheme.space8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space16,
            AppTheme.space6,
            AppTheme.space16,
            AppTheme.space4,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: colors.surfaceBorderStrong,
                width: AppTheme.hairline,
              ),
              boxShadow: AppTheme.floatingShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dock != null) ...[
                    dock,
                    Divider(
                      height: AppTheme.hairline,
                      thickness: AppTheme.hairline,
                      color: colors.surfaceBorderStrong,
                    ),
                  ],
                  Padding(padding: const EdgeInsets.all(_inset), child: tabs),
                ],
              ),
            ),
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
    final colors = context.colors;
    final color = selected ? colors.primary : colors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? data.selectedIcon : data.icon,
              size: AppTheme.icon22,
              color: color,
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: colors.uiSmall.copyWith(
                fontSize: AppTheme.font11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
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
    final itemInset = collapsed ? AppTheme.space8 : AppTheme.space12;

    return AnimatedContainer(
      duration: navRailMotion,
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
                                tooltip: AppCommands.tooltip(
                                  t.terminal.selectDevice,
                                  AppCommand.newSession,
                                ),
                                icon: PhosphorIconsRegular.plus,
                                onTap: () => AppCommands.instance.run(
                                  AppCommand.newSession,
                                ),
                              ),
                          ],
                        ),
                        for (final session in sessions)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTheme.space2,
                            ),
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
    final manager = ref.read(sshSessionManagerProvider);
    final sessionName = session.multiplexer.isPersistent
        ? manager.muxNameFor(session.id)
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
      unread: manager.hasUnreadNotice(session.id),
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

/// The card asking to share anonymous stats, over the home screen just above
/// the navigation bar, while [AnalyticsService.asking] is up. It belongs to
/// the home screen only: [visible] is false on any other tab or behind the
/// terminal, and leaving home takes the question down for good.
class _AnalyticsAskOverlay extends StatelessWidget {
  const _AnalyticsAskOverlay({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final service = AnalyticsService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: service.asking,
      builder: (context, asking, _) {
        if (!asking || !visible) return const SizedBox.shrink();
        return Positioned(
          left: AppTheme.space12,
          right: AppTheme.space12,
          bottom: MediaQuery.paddingOf(context).bottom + AppTheme.space12,
          child: SafeArea(
            top: false,
            bottom: false,
            child: DesktopContentWidth(
              child: AnalyticsAskCard(
                onAnswer: (granted) => unawaited(service.setConsent(granted)),
              ),
            ),
          ),
        );
      },
    );
  }
}

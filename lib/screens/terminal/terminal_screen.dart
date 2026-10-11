import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/port_forwarding_rule.dart';
import '../../models/remote_shell.dart';
import '../../models/session_tab.dart';
import '../../models/snippet.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/port_forwarding_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../providers/ssh_connection_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../providers/terminal_overlay_provider.dart' show SiblingScope;
import '../../services/app/app_commands.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/settings/action_dock_settings.dart';
import '../../services/settings/floating_dock_settings.dart';
import '../../services/settings/sidebar_settings.dart';
import '../../services/settings/tab_bar_settings.dart';
import '../../services/settings/terminal_settings.dart';
import '../../services/snippets/snippet_launcher.dart';
import '../../services/ssh/ssh_session_manager.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../../widgets/profiles/profile_avatar.dart';
import '../../widgets/sftp/sftp_browser_view.dart';
import '../../widgets/snippets/snippet_args_dialog.dart';
import '../../widgets/snippets/snippet_picker_panel.dart';
import '../../widgets/ssh/connection_log_sheet.dart';
import '../../widgets/terminal/action_dock_menu.dart';
import '../../widgets/terminal/add_session_sheet.dart';
import '../../widgets/terminal/floating_action_dock.dart';
import '../../widgets/terminal/rename_session_dialog.dart';
import '../../widgets/terminal/session_quick_sheet.dart';
import '../../widgets/terminal/session_tab_pill.dart';
import '../../widgets/terminal/session_view.dart';
import '../../widgets/terminal/special_keys_toolbar.dart';
import '../../widgets/terminal/split_pane_chrome.dart'
    show tabDragProxyDecorator;
import '../../widgets/terminal/split_tab_layout.dart';
import '../../widgets/terminal/tab_menu_parts.dart';
import '../../widgets/terminal/terminal_pane.dart';
import '../../widgets/terminal/terminal_tab_pill.dart';
import '../../widgets/terminal/tunnels_panel.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/app_sheet.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/nav_rail.dart';
import '../../widgets/ui/reorder_drag.dart';
import '../../widgets/ui/section_header.dart';
import '../../widgets/ui/section_navigator.dart';
import '../settings/terminal_appearance_screen.dart';
import '../settings/toolbar_profiles_screen.dart';
import 'state/session_swipe.dart';
import 'state/tab_reconciler.dart';
import 'state/tab_strip_controller.dart';

/// Vertical padding inside the strip around a tab pill.
const _kTabStripPaddingY = 6.0;

/// The status avatar sets a floor: a single-line tab is still at least this
/// tall, whatever the font scale is doing.
const _kTabAvatarSize = 24.0;

/// Floor for the strip as a whole. The measurement below only says what the
/// tabs *need*; at ordinary font sizes that is tighter than the strip should
/// look, so it never goes under this.
const _kTabBarMinHeight = 58.0;

/// Height of the tab strip, for the font scale currently in effect.
///
/// A fixed height was a promise the tabs still fit inside it. Raise the
/// system font (or display) scale far enough and the pill needs more room
/// than the strip has, so its labels render outside their own background and
/// border. Measuring the labels instead means the strip is always exactly as
/// tall as its tallest tab needs.
double terminalTabBarHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final labels = scaler.scale(kSessionTabNameSize) * kSessionTabLineHeight;
  final needed =
      math.max(labels, _kTabAvatarSize) +
      kSessionTabPillPaddingY * 2 +
      _kTabStripPaddingY * 2;
  return math.max(needed, _kTabBarMinHeight);
}

enum _TabConnectionAction {
  updateAgent,
  manageTunnels,
  viewLog,
  splitWith,
  unsplit,
  rename,
  close,
  endSession,
  reconnect,
}

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    super.key,
    required this.initialSessionId,
    required this.initialProfile,
    this.siblingScope = SiblingScope.all,
    this.onClose,
    this.onHide,
    this.navItems = const [],
    this.onNavigate,
  });

  final String initialSessionId;
  final SshProfile initialProfile;

  /// Which other tabs to pull into the strip alongside [initialSessionId].
  final SiblingScope siblingScope;
  final VoidCallback? onClose;
  final VoidCallback? onHide;

  /// The app's own destinations, drawn at the top of the rail on a desktop in
  /// place of the back button: there the rail is the same sidebar the rest
  /// of the app has, and leaving the terminal is picking somewhere else to
  /// go, not backing out of it.
  final List<ShellNavItem> navItems;
  final ValueChanged<int>? onNavigate;

  @override
  ConsumerState<TerminalScreen> createState() => TerminalScreenState();
}

/// Every page renders its own view mode, active or not: a tab sliding in
/// during a swipe has to already be the file browser it will still be when
/// the swipe lands, not a terminal that swaps over afterwards.
///
/// The session area is a column, not a stack with the toolbar's measured
/// height subtracted from the session's padding: the toolbar takes the room
/// it needs and the session gets the rest, which is the same answer without
/// measuring a render box or being told to measure it again. What the
/// keyboard takes is already gone from the height the column is given,
/// since the Scaffold below resizes for it.
///
/// The floating dock is a sibling of the swipe area, not inside each
/// `SessionView`, so switching tabs can never leave it stuck open in one
/// and closed in another - one instance follows whichever tab is active,
/// the same way the special-keys toolbar does. A swiped-to page is
/// translated, not repositioned, so the `Stack` never sees an overflowing
/// child and skips its own clip - a repositioned page would paint straight
/// over the landscape tab rail beside it, reading as the sidebar
/// disappearing for the length of the swipe.
///
/// Moving the tab strip to the bottom takes nothing from the session: it is
/// the same height wherever it sits, so the pty is never resized for it. In
/// landscape the strip becomes a rail down the side instead, the same trade
/// `MainShell` makes for its own nav - landscape frees up width instead of
/// height, which the strip wants more than the terminal does. Its
/// `SafeArea`'s `padding` is already zero at the bottom while the keyboard
/// is up, since the navigation bar is behind it with nothing left to keep
/// clear of.
class TerminalScreenState extends ConsumerState<TerminalScreen>
    with SingleTickerProviderStateMixin {
  /// Owns the sessions, which one is active, each tab's view mode, focus
  /// history and splits - everything that is pure state, with no
  /// `BuildContext`, `ref` or manager call anywhere near it.
  late final TabStripController _controller;

  final ScrollController _tabScrollController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};
  final Map<String, GlobalKey<SftpBrowserViewState>> _sftpKeys = {};
  final Map<String, GlobalKey<SessionViewState>> _sessionKeys = {};
  final Set<String> _updatingAgentProfiles = {};

  /// Held down, a split's divider must not also be read as a tab swipe - this
  /// is [SplitTabLayout]'s way of telling the swipe gesture to stand down.
  bool _dividerHeld = false;

  /// Tells a tab closed elsewhere from one this screen has only just added.
  late final TabReconciler _reconciler;

  late final SessionSwipeController _swipe;

  late final SshSessionManager _manager = ref.read(sshSessionManagerProvider);

  final GlobalKey _dockButtonKey = GlobalKey();
  late bool _floatingDockEnabled;
  late bool _toolbarEnabled;
  late TabBarPosition _tabBarPosition;

  List<(String, SshProfile)> get _sessions => _controller.sessions;

  int get _activeIndex => _controller.activeIndex;

  SessionViewMode _modeFor(String sessionId) => _controller.modeFor(sessionId);

  SessionViewMode get _activeMode => _modeFor(_sessions[_activeIndex].$1);

  List<String> get _sessionIds => _controller.sessionIds;

  /// The strip's entries - a split is one, holding both of its sessions.
  List<List<String>> get _entries => _controller.entries;

  int _entryIndexOf(String sessionId) => _controller.entryIndexOf(sessionId);

  int get _activeEntryIndex => _entryIndexOf(_sessions[_activeIndex].$1);

  void _setMode(String sessionId, SessionViewMode mode) {
    _controller.setMode(sessionId, mode);
  }

  /// What each session action does for [session]: the dock's tiles, the
  /// desktop's palette and its action bar all run these. Absent are the ones
  /// that cannot apply right now - tunnels without a connection, rename
  /// without a persistent session.
  Map<DockAction, VoidCallback> _dockActionsFor((String, SshProfile) session) {
    final state = ref.read(sshConnectionProvider(session));
    final connected = state.status == ConnectionStatus.connected;
    final persistent = state.multiplexer.isPersistent;
    return {
      DockAction.insertSnippet: () => unawaited(
        showSnippetSpotlight(context, onSelect: _handleSnippetSelected),
      ),
      DockAction.uploadFile: () {
        final sessionState = _sessionKeys[session.$1]?.currentState;
        if (sessionState != null) {
          unawaited(sessionState.uploadFileToTerminal());
        }
      },
      DockAction.paste: () {
        final sessionState = _sessionKeys[session.$1]?.currentState;
        if (sessionState != null) {
          unawaited(sessionState.handlePaste());
        }
      },
      DockAction.search: () =>
          _sessionKeys[session.$1]?.currentState?.openSearch(),
      DockAction.copyPath: () =>
          unawaited(_sessionKeys[session.$1]?.currentState?.copyCurrentPath()),
      DockAction.newSession: () => unawaited(_showAddSessionSheet()),
      if (connected) DockAction.tunnels: () => _showTunnelsSheet(session.$1),
      if (persistent)
        DockAction.rename: () => unawaited(_renameSession(session, state)),
      DockAction.viewLog: () =>
          unawaited(showConnectionLogSheet(context, session)),
    };
  }

  /// Copying the current path needs the agent's cwd tracking, so it is the
  /// only action gated on [Multiplexer.termphin].
  bool _dockActionEnabled((String, SshProfile) session, DockAction action) =>
      action != DockAction.copyPath ||
      ref.read(sshConnectionProvider(session)).multiplexer ==
          Multiplexer.termphin;

  /// The session actions as a toolbar over the terminal: a desktop has
  /// no thumb for a floating button, and a row of labelled actions in reach
  /// of the pointer is what a desktop app would put there. It spans the
  /// terminal's width - the tab rail beside it keeps the full height - with
  /// the actions starting at its left end; should a narrow window not fit
  /// them, it scrolls rather than stacking a label.
  Widget _buildDesktopActionBar((String, SshProfile) session) {
    final t = Translations.of(context);
    final colors = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([
        actionDockSettings.order,
        actionDockSettings.hidden,
      ]),
      builder: (context, _) {
        final builders = _dockActionsFor(session);
        final hidden = actionDockSettings.hidden.value;
        final actions = [
          for (final action in actionDockSettings.order.value)
            if (!hidden.contains(action) && builders[action] != null) action,
        ];
        return Container(
          key: const ValueKey('desktopActionBar'),
          height: 38,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: colors.backgroundPrimary,
            border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextButton.icon(
                      key: ValueKey('actionBar-${action.name}'),
                      onPressed: _dockActionEnabled(session, action)
                          ? builders[action]
                          : null,
                      icon: Icon(dockActionIcon(action), size: 15),
                      label: Text(
                        _desktopActionLabel(t, action),
                        maxLines: 1,
                        softWrap: false,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        textStyle: colors.uiSmall.copyWith(fontSize: 12.5),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 30),
                        shape: const RoundedRectangleBorder(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A bar label: on one line - the phone's tile breaks Fast upload in two -
  /// and with the action's shortcut after it, where it has one.
  String _desktopActionLabel(Translations t, DockAction action) {
    final label = dockActionLabel(t, action).replaceAll('\n', ' ');
    final command = switch (action) {
      DockAction.uploadFile => AppCommand.uploadFile,
      DockAction.search => AppCommand.findInTerminal,
      DockAction.newSession => AppCommand.newSession,
      _ => null,
    };
    final shortcut = command == null
        ? null
        : AppCommands.shortcutLabel(command);
    return shortcut == null ? label : '$label ($shortcut)';
  }

  /// The one place to reach a snippet or a one-shot tool (upload, paste,
  /// tunnels, ...) - the floating dock opens it directly, anchored to
  /// wherever that button currently is. Destructive actions (detach, end
  /// session) stay off the list.
  /// Which of these show and in what order is the user's call, from the
  /// command palette section of Settings - reloaded fresh on every open so
  /// a change there is never stale by the time this next shows.
  Future<void> _openActionDock((String, SshProfile) session) async {
    final t = Translations.of(context);
    final builders = _dockActionsFor(session);

    await actionDockSettings.load();
    if (!mounted) return;
    final hidden = actionDockSettings.hidden.value;
    final tools = [
      for (final action in actionDockSettings.order.value)
        if (!hidden.contains(action) && builders[action] != null)
          SpotlightTool(
            icon: dockActionIcon(action),
            label: dockActionLabel(t, action),
            enabled: _dockActionEnabled(session, action),
            onSelect: builders[action]!,
          ),
    ];

    final buttonBox =
        _dockButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final anchorRect = buttonBox != null
        ? (buttonBox.localToGlobal(Offset.zero) & buttonBox.size)
        : Rect.fromLTWH(
            MediaQuery.of(context).size.width - 56,
            MediaQuery.of(context).size.height - 200,
            44,
            44,
          );

    unawaited(
      showActionDockMenu(context, anchorRect: anchorRect, tools: tools),
    );
  }

  /// A tab's label is the session's name, which the manager owns: a rename
  /// changes it underneath the strip, which would otherwise keep showing the
  /// old one until something else happened to rebuild the screen. The manager
  /// only notifies on session lifecycle, never per byte of output.
  void _onManagerChanged() {
    if (!mounted) return;
    _pruneTabsClosedElsewhere();
    if (mounted) setState(() {});
  }

  void _onFloatingDockSettingChanged() {
    if (!mounted) return;
    setState(() => _floatingDockEnabled = floatingDockSettings.enabled.value);
  }

  /// The padding under the session is what gives the toolbar its room, so
  /// dropping the toolbar hands those rows back to the terminal on its own.
  void _onToolbarEnabledChanged() {
    if (!mounted) return;
    setState(() => _toolbarEnabled = toolbarSettings.enabled.value);
  }

  void _onTabBarPositionChanged() {
    if (!mounted) return;
    setState(() => _tabBarPosition = tabBarPositionSetting.value);
  }

  @override
  void dispose() {
    tabBarPositionSetting.removeListener(_onTabBarPositionChanged);
    _tabScrollController.dispose();
    _swipe.dispose();
    _controller.dispose();
    toolbarSettings.enabled.removeListener(_onToolbarEnabledChanged);
    floatingDockSettings.enabled.removeListener(_onFloatingDockSettingChanged);
    _manager.removeListener(_onManagerChanged);
    super.dispose();
  }

  /// The swipe is blocked while a selection handle in the terminal, or the
  /// handle between split panes, is being dragged - both own the pointer
  /// and must not have it taken away mid-drag.
  ///
  /// Which tabs come along as restored siblings is
  /// `SshSessionManager.restorableSession` - shared so the session dock
  /// counts exactly what a tap on it opens. How wide the net is cast is
  /// this screen's own business: a single session row wants only itself, a
  /// machine card wants every tab that belongs to it, and the dock / cold
  /// start resume the whole strip regardless of which profile each tab is
  /// under.
  ///
  /// Once scrolled into view, every restored tab is connected: everything
  /// that made it into the strip is either already attached or meant to be,
  /// so connecting the lot is exactly the intent. Only the one actually
  /// tapped stays around to show an error if it can't connect, though - a
  /// sibling pulled in on the strength of a stale `wasConnected` flag alone
  /// gets one silent try and, if the remote session is simply gone, is
  /// forgotten rather than sitting in the strip forever as a tab the user
  /// never asked for and can't use.
  @override
  void initState() {
    super.initState();
    _swipe =
        SessionSwipeController(
          vsync: this,
          tabCount: () => _entries.length,
          activeIndex: () => _activeEntryIndex,
          onCommit: _onSwipeCommitted,
          isBlocked: () => terminalSelectionHandleHeld.value || _dividerHeld,
        )..addListener(() {
          if (mounted) setState(() {});
        });
    toolbarSettings.enabled.addListener(_onToolbarEnabledChanged);
    floatingDockSettings.enabled.addListener(_onFloatingDockSettingChanged);
    _floatingDockEnabled = floatingDockSettings.enabled.value;
    _toolbarEnabled = toolbarSettings.enabled.value;
    tabBarPositionSetting.addListener(_onTabBarPositionChanged);
    _tabBarPosition = tabBarPositionSetting.value;

    final manager = _manager;
    manager.addListener(_onManagerChanged);
    _reconciler = TabReconciler(manager)..seed();
    final restoredTabs = switch (widget.siblingScope) {
      SiblingScope.none => const <ActiveSessionView>[],
      SiblingScope.sameProfile =>
        manager.tabs
            .where((s) => s.profile.id == widget.initialProfile.id)
            .where(manager.restorableSession)
            .toList(),
      SiblingScope.all => manager.restorableTabs,
    };

    final isExisting = restoredTabs.any((s) => s.id == widget.initialSessionId);

    final initialSessions = isExisting
        ? restoredTabs.map((s) => (s.id, s.profile)).toList()
        : [
            (widget.initialSessionId, widget.initialProfile),
            ...restoredTabs.map((s) => (s.id, s.profile)),
          ];

    var initialActiveIndex = initialSessions.indexWhere(
      (e) => e.$1 == widget.initialSessionId,
    );
    if (initialActiveIndex < 0) initialActiveIndex = 0;

    _controller = TabStripController(
      sessions: initialSessions,
      activeIndex: initialActiveIndex,
    );

    for (final s in _sessions) {
      _tabKeys[s.$1] = GlobalKey();
      _sftpKeys[s.$1] = GlobalKey<SftpBrowserViewState>();
      _sessionKeys[s.$1] = GlobalKey<SessionViewState>();
    }

    _controller.noteFocus(_sessions[_activeIndex].$1);
    _restoreSplits(manager);
    unawaited(manager.setActiveSession(_sessions[_activeIndex].$1));

    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSessionTab(_sessions[_activeIndex].$1, animated: false);
      for (final key in _sessions) {
        unawaited(
          _connectSession(key, autoRestored: key.$1 != widget.initialSessionId),
        );
      }
    });
  }

  /// Puts back the splits the strip last had, where both tabs made it back.
  void _restoreSplits(SshSessionManager manager) {
    final changed = _controller.restoreSplits(manager.savedSplits);
    if (changed) manager.reorderSessions(_sessionIds);
  }

  /// Saves the strip's splits. [also] names tabs just taken out of it, whose
  /// splits have to be dropped too.
  void _persistSplits({Iterable<String> also = const []}) {
    final ids = _sessionIds;
    _manager.saveSplits([...ids, ...also], _controller.saved(ids));
  }

  /// Close enough without waiting on a layout pass to measure. A flat 80x24
  /// would undersize most screens and force a resize right after connect,
  /// which on Windows makes ConPTY repaint instead of drawing once.
  /// `verticalChrome` is the app bar, tab strip, key toolbar and safe areas,
  /// roughly.
  ({int cols, int rows}) _estimatePtySize() {
    final mediaQuery = MediaQuery.of(context);
    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(
          fontFamily: terminalSettings.fontFamily.value,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cellWidth = painter.width;
    final cellHeight = painter.height * terminalSettings.lineHeight.value;
    const verticalChrome = 220.0;
    const horizontalChrome = 24.0;
    final availableWidth = mediaQuery.size.width - horizontalChrome;
    final availableHeight =
        mediaQuery.size.height - mediaQuery.padding.vertical - verticalChrome;
    final cols = (availableWidth / cellWidth).floor().clamp(20, 300);
    final rows = (availableHeight / cellHeight).floor().clamp(10, 300);
    return (cols: cols, rows: rows);
  }

  /// Connects a tab. The native layer installs a missing helper atomically.
  Future<void> _connectSession(
    (String, SshProfile) key, {
    bool autoRestored = false,
  }) async {
    final (:cols, :rows) = _estimatePtySize();
    await ref
        .read(sshConnectionProvider(key).notifier)
        .connect(initialWidth: cols, initialHeight: rows);
    if (!autoRestored || !mounted) return;
    final status = ref.read(sshConnectionProvider(key)).status;
    if (status == ConnectionStatus.error) {
      unawaited(_forgetFailedRestore(key.$1));
    }
  }

  /// Drops a tab that was pulled into the strip automatically (never tapped
  /// by the user this run) and then failed to ever connect - the remote
  /// session it pointed at is gone, so there is nothing to keep offering a
  /// retry on. Unlike [_removeSession], this forgets the tab outright rather
  /// than marking it detached-and-resumable: it never actually attached, so
  /// there is nothing to resume.
  Future<void> _forgetFailedRestore(String sessionId) async {
    if (!mounted) return;
    if (!_sessionIds.contains(sessionId)) return;
    _tabKeys.remove(sessionId);
    _sftpKeys.remove(sessionId);
    _sessionKeys.remove(sessionId);
    _controller.forgetFailedRestore(
      sessionId,
      persist: () => _persistSplits(also: [sessionId]),
    );
    await _manager.forgetTab(sessionId);
    if (_sessions.isEmpty && mounted) widget.onClose?.call();
  }

  /// Closes the tab, leaving the persistent session running on the server.
  Future<void> _closeSession(String sessionId) => _removeSession(sessionId);

  /// Closes the tab, then kills the persistent session on the server - in
  /// that order, so the tab never waits on the server to answer.
  Future<void> _endSession(String sessionId) async {
    final index = _sessions.indexWhere((item) => item.$1 == sessionId);
    if (index < 0) return;
    final profile = _sessions[index].$2;
    final t = Translations.of(context);
    final displayHost = ref.read(anonymizeProvider)
        ? IdentityAnonymizer.host(profile.id)
        : profile.host;
    final confirmed = await showConfirmDialog(
      context,
      title: t.session.endSessionTitle,
      message: t.session.endSessionConfirm(host: displayHost),
      confirmLabel: t.session.endSession,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final current = _sessions.indexWhere((item) => item.$1 == sessionId);
    if (current < 0) return;
    final key = _sessions[current];
    final notifyContext = AppNotifications.anchorOf(context);
    final ending = ref.read(sshConnectionProvider(key).notifier).endSession();
    _dropTabs({sessionId});
    try {
      await ending;
    } catch (error) {
      if (!notifyContext.mounted) return;
      AppNotifications.error(
        notifyContext,
        t.session.endSessionFailed(
          host: displayHost,
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Detaches and drops the tab. Detaching leaves the remote session running
  /// on the server, but the strip is for connected sessions only - this one
  /// now belongs in the new-session sheet, which is where it gets picked
  /// back up.
  Future<void> _removeSession(String sessionId) async {
    final initialIndex = _sessions.indexWhere((item) => item.$1 == sessionId);
    if (initialIndex < 0) return;
    final key = _sessions[initialIndex];
    final disconnecting = ref
        .read(sshConnectionProvider(key).notifier)
        .disconnect();
    _dropTabs({sessionId});
    try {
      await disconnecting;
    } catch (_) {}
  }

  /// Takes [ids] out of the strip and repairs the selection around them.
  ///
  /// Shared by the strip's own close/detach path and by [_pruneTabsClosedElsewhere],
  /// so a tab removed from the home screen leaves exactly the way one removed
  /// from the tab's own menu does.
  void _dropTabs(Set<String> ids) {
    if (!_sessionIds.any(ids.contains)) return;
    _reconciler.forget(ids);
    for (final id in ids) {
      _tabKeys.remove(id);
      _sftpKeys.remove(id);
      _sessionKeys.remove(id);
    }
    _controller.dropTabs(ids, persist: () => _persistSplits(also: ids));
    if (_sessions.isEmpty && mounted) {
      widget.onClose?.call();
    } else {
      _scrollToSessionTab(_sessions[_activeIndex].$1);
      unawaited(_manager.setActiveSession(_sessions[_activeIndex].$1));
    }
  }

  /// Drops tabs that were detached or ended from somewhere other than this
  /// strip - the home screen's session row menu is the one that matters.
  ///
  /// The manager is the only thing that hears about those, and repainting on
  /// its notification is not enough: `_sessions` is this screen's own list,
  /// built once in `initState` and never rebuilt, because the strip outlives
  /// being hidden. Without this a detached tab keeps its place in the bar,
  /// and reopening the strip from the dock shows it still sitting there.
  ///
  /// Only ids the manager has already acknowledged are eligible. A tab added
  /// by [_attachTab] is in `_sessions` a moment before `startSession`
  /// registers it, and pruning on that gap would delete the tab being opened.
  void _pruneTabsClosedElsewhere() {
    final gone = _reconciler.closedElsewhere(_sessions.map((item) => item.$1));
    if (gone.isEmpty) return;
    _dropTabs(gone);
  }

  /// Leaving a detached tab visible in the strip only pays off if selecting
  /// it attaches right away - nobody should have to look at a "Re-attach"
  /// card and tap it a second time.
  void _attachIfNeeded((String, SshProfile) key) {
    final status = ref.read(sshConnectionProvider(key)).status;
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      unawaited(_connectSession(key));
    }
  }

  void _scrollToSessionTab(
    String sessionId, {
    bool animated = true,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabContext = _tabKeys[sessionId]?.currentContext;
      if (tabContext == null) {
        if (attempt < 2) {
          _scrollToSessionTab(
            sessionId,
            animated: animated,
            attempt: attempt + 1,
          );
        }
        return;
      }
      Scrollable.ensureVisible(
        tabContext,
        alignment: 0.5,
        duration: animated ? AppTheme.motionSlow : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Brings the tab just appended to the strip into view.
  ///
  /// Deliberately not [_scrollToSessionTab]. That measures the tab's element
  /// and asks `ensureVisible` to reveal it, which clamps to the scroll extent
  /// the strip has built so far - with wide tabs (a named session leads with
  /// its own name, so labels run long) the extent is still short of the new
  /// tab and the scroll stops before reaching it. Re-issuing `ensureVisible`
  /// only fights the animation it started. Driving the controller to the end
  /// instead needs no element at all, and each pass builds more of the lazy
  /// strip until the extent stops growing.
  void _scrollStripToEnd({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabScrollController.hasClients) return;
      final position = _tabScrollController.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() < 0.5) return;
      _tabScrollController.jumpTo(target);
      if (attempt < 4) _scrollStripToEnd(attempt: attempt + 1);
    });
  }

  void _selectSession(String sessionId, {bool haptic = true}) {
    final changed = _controller.select(sessionId);
    if (changed == null) return;
    if (changed && haptic) HapticFeedback.selectionClick();
    _scrollToSessionTab(sessionId);
    unawaited(_manager.setActiveSession(sessionId));
    final index = _sessions.indexWhere((item) => item.$1 == sessionId);
    _attachIfNeeded(_sessions[index]);
    focusActiveTerminal();
  }

  /// A tap on a tab: the switch at once, then the page slides in, unless the
  /// system asks for less motion. A split partner shares the page, so
  /// focusing it moves nothing.
  void _onTabTapped(String sessionId) {
    final before = _activeEntryIndex;
    _selectSession(sessionId);
    final after = _activeEntryIndex;
    if (after == before || MediaQuery.disableAnimationsOf(context)) return;
    _swipe.slideIn(from: before, to: after);
  }

  /// A swipe that settled on another tab. The gesture decides when; making
  /// that tab active is this screen's business, and the same work
  /// [_selectSession] does bar the haptic, which the gesture already gave.
  void _onSwipeCommitted(int entryIndex) {
    if (!mounted) return;
    _controller.selectEntry(entryIndex);
    final session = _sessions[_activeIndex];
    _scrollToSessionTab(session.$1);
    unawaited(_manager.setActiveSession(session.$1));
    _attachIfNeeded(session);
  }

  Widget _buildSwipeSessionPage({
    required int index,
    required int activeIndex,
    required double offset,
    required double width,
    required Widget child,
  }) {
    final targetIndex = _swipe.targetIndex;
    final isActive = index == activeIndex;
    final isTarget = index == targetIndex;
    final visible = isActive || isTarget;

    var horizontalOffset = 0.0;
    if (isActive) {
      horizontalOffset = offset;
    } else if (isTarget) {
      horizontalOffset = offset + (index > activeIndex ? width : -width);
    }

    return Positioned.fill(
      child: Offstage(
        offstage: !visible,
        child: IgnorePointer(
          ignoring: !isActive || targetIndex != null || _swipe.isAnimating,
          child: Transform.translate(
            key: ValueKey('sessionSwipePage-$index'),
            offset: Offset(horizontalOffset, 0),
            child: child,
          ),
        ),
      ),
    );
  }

  /// A drag in the strip moves an entry, so a split moves as one.
  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final ids = _controller.reorder(oldIndex, newIndex);
    HapticFeedback.mediumImpact();
    _manager.reorderSessions(ids);
  }

  /// Splits [target] with [other], which lands beside it and takes focus.
  void _splitTabs(String other, String target) {
    final ids = _controller.split(other, target);
    _manager.reorderSessions(ids);
    _persistSplits();
    _selectSession(other, haptic: false);
  }

  void _swapPanes(String sessionId) {
    final ids = _controller.swap(sessionId);
    _manager.reorderSessions(ids);
    _persistSplits();
  }

  void _unsplit(String sessionId) {
    _controller.unsplit(sessionId);
    _persistSplits();
  }

  void _addSession(SshProfile profile, {String? sessionId, String? splitWith}) {
    final id = _controller.add(
      profile,
      sessionId: sessionId,
      splitWith: splitWith,
    );
    final key = (id, profile);
    _tabKeys[id] = GlobalKey();
    _sftpKeys[id] = GlobalKey<SftpBrowserViewState>();
    _sessionKeys[id] = GlobalKey<SessionViewState>();
    _manager.reorderSessions(_sessionIds);
    if (splitWith != null) _persistSplits();
    unawaited(_manager.setActiveSession(id));
    if (splitWith == null) {
      _scrollStripToEnd();
    } else {
      _scrollToSessionTab(id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_connectSession(key));
    });
  }

  /// The sheet draws its own handle, since the content is a
  /// `DraggableScrollableSheet`.
  Future<void> _showAddSessionSheet({String? splitWith}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

    if (!mounted) return;
    final profiles = ref.read(profilesProvider);
    await showAppSheet<void>(
      context: context,
      handle: false,
      builder: (sheetCtx) {
        return AddSessionSheetContent(
          profiles: profiles,
          resumableFor: _manager.resumableTabsForProfile,
          onSelect: (p) {
            Navigator.of(sheetCtx).pop();
            _addSession(p, splitWith: splitWith);
          },
          onAttach: (tabId, profile) {
            Navigator.of(sheetCtx).pop();
            _attachTab(tabId, profile, splitWith: splitWith);
          },
        );
      },
    );
  }

  /// Renames the tab's persistent session. Uses the live connection when connected
  /// (no extra handshake); otherwise falls back to a short-lived rename over
  /// the last known session name.
  Future<void> _renameSession(
    (String, SshProfile) session,
    SshConnectionState state,
  ) async {
    final manager = _manager;
    final currentName = manager.muxNameFor(session.$1);
    if (currentName == null) return;

    await showRenameSessionDialog(
      context,
      currentName: currentName,
      onRename: (newName) {
        if (state.status == ConnectionStatus.connected) {
          return manager.renameSession(session.$1, newName);
        }
        return manager.renameRemoteSession(session.$2, currentName, newName);
      },
    );
  }

  /// Focuses the tab bound to [tabId], adding it first if it is not open yet.
  /// `_selectSession` attaches on its own if the tab isn't connected.
  void _attachTab(String tabId, SshProfile profile, {String? splitWith}) {
    final existing = _sessions.indexWhere((item) => item.$1 == tabId);
    if (existing >= 0) {
      if (splitWith != null && _controller.canJoin(tabId, splitWith)) {
        _splitTabs(tabId, splitWith);
      }
      _selectSession(tabId);
      return;
    }
    _addSession(profile, sessionId: tabId, splitWith: splitWith);
  }

  /// A tab's label as the strip spells it out: "session - machine" for a
  /// named session, the machine alone otherwise.
  String _tabLabel((String, SshProfile) session) {
    final displayName = ref.read(anonymizeProvider)
        ? IdentityAnonymizer.name(session.$2.id)
        : session.$2.name;
    final state = ref.read(sshConnectionProvider(session));
    final sessionName = state.multiplexer.isPersistent
        ? _manager.muxNameFor(session.$1)
        : null;
    return sessionName != null
        ? '${SessionTab.displayName(sessionName)} - $displayName'
        : displayName;
  }

  /// Picks what [targetId] shares the screen with: a tab already open on its
  /// own, or a new connection.
  Future<void> _showSplitPicker(String targetId) async {
    final t = Translations.of(context);
    final candidates = [
      for (final entry in _entries)
        if (entry.length == 1 && entry.first != targetId)
          _sessions.firstWhere((s) => s.$1 == entry.first),
    ];
    await showAppSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SectionHeader(t.terminal.splitWithTitle),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final session in candidates)
                    ListTile(
                      key: ValueKey('splitCandidate-${session.$1}'),
                      leading: ProfileAvatar(
                        iconName: session.$2.iconName,
                        colorHex: session.$2.colorHex,
                        size: 28,
                      ),
                      title: Text(
                        _tabLabel(session),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _splitTabs(session.$1, targetId);
                      },
                    ),
                  ListTile(
                    key: const ValueKey('splitCandidateNew'),
                    leading: SizedBox.square(
                      dimension: 28,
                      child: Icon(
                        PhosphorIconsRegular.plus,
                        size: 20,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    title: Text(t.terminal.splitNewConnection),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      unawaited(_showAddSessionSheet(splitWith: targetId));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTunnelsSheet(String sessionId) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

    if (!mounted) return;
    await showAppSheet<void>(
      context: context,
      builder: (sheetCtx) {
        return TunnelsPanel(sessionId: sessionId);
      },
    );
  }

  /// [atBottom] turns the edge line to face the terminal above it. Under it
  /// the key toolbar draws its own, which parts the tabs from the keys.
  ///
  /// The gaps either side of the strip are built from two halves - the back
  /// button's own padding and the scroll view's - so they have to match, or
  /// the arrow sits closer to the tabs than the plus does.
  Widget _buildTabBar({bool atBottom = false}) {
    final t = Translations.of(context);
    final borderColor = Theme.of(context).dividerColor;
    final barBackground = Theme.of(context).scaffoldBackgroundColor;
    final edge = BorderSide(color: borderColor);

    return Container(
      key: const ValueKey('terminalTabBar'),
      height: terminalTabBarHeight(context),
      decoration: BoxDecoration(
        color: barBackground,
        border: atBottom ? Border(top: edge) : Border(bottom: edge),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 3),
            child: _buildTabBarAction(
              key: const ValueKey('tabBarBackButton'),
              tooltip: t.common.back,
              icon: PhosphorIconsFill.arrowLeft,
              onTap: widget.onHide,
            ),
          ),
          Expanded(
            child: _buildTabList(
              axis: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                3,
                _kTabStripPaddingY,
                3,
                _kTabStripPaddingY,
              ),
            ),
          ),
          if (_terminalLive()) ...[
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: _buildQuickSettingsButton(),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 3, right: 6),
            child: _buildAddTabButton(),
          ),
        ],
      ),
    );
  }

  /// Landscape's replacement for [_buildTabBar] - the same tab pills, back
  /// button and add button, just stood up on their side into a fixed-width
  /// rail instead of a strip along the top.
  ///
  /// It collapses on the same hamburger, and off the same
  /// [sidebarCollapsedSetting], as `MainShell`'s nav rail. The two are the
  /// same strip down the same edge and are never on screen together, so
  /// collapsing one and finding the other still at full width would read as
  /// the sidebar having forgotten.
  Widget _buildTabRail() {
    return ValueListenableBuilder<bool>(
      valueListenable: sidebarCollapsedSetting,
      builder: (context, collapsed, _) {
        if (_desktopRail) return _buildDesktopRailBody(collapsed);
        return _buildTabRailBody(collapsed);
      },
    );
  }

  bool get _desktopRail => isDesktopPlatform && widget.navItems.isNotEmpty;

  /// The desktop's sidebar while a session is on screen: the app's
  /// destinations, then the sessions, laid out like `MainShell`'s own so the
  /// strip does not move when the terminal comes and goes. Painted in the
  /// terminal's scheme like the rest of a session's chrome, as on a phone.
  Widget _buildDesktopRailBody(bool collapsed) {
    final t = Translations.of(context);
    final width = navRailWidth(collapsed);
    final itemInset = collapsed ? 8.0 : 12.0;
    return Builder(
      builder: (context) => AnimatedContainer(
        duration: AppTheme.motionSlow,
        curve: AppTheme.interactiveCurve,
        width: width,
        decoration: BoxDecoration(
          color: context.colors.backgroundPrimary,
          border: Border(
            right: BorderSide(color: context.colors.surfaceBorder),
          ),
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: width,
            maxWidth: width,
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
                Padding(
                  padding: EdgeInsets.fromLTRB(itemInset, 4, itemInset, 0),
                  child: Column(
                    children: [
                      for (var i = 0; i < widget.navItems.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SidebarNavItem(
                            data: widget.navItems[i],
                            selected: false,
                            collapsed: collapsed,
                            onTap: () => widget.onNavigate?.call(i),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: itemInset),
                  child: Row(
                    children: [
                      Expanded(
                        child: SidebarSectionLabel(
                          t.nav.sessions,
                          collapsed: collapsed,
                        ),
                      ),
                      if (!collapsed) _buildAddTabButton(),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildTabList(
                    axis: Axis.vertical,
                    padding: EdgeInsets.fromLTRB(itemInset, 3, itemInset, 12),
                    stretch: !collapsed,
                    collapsed: collapsed,
                  ),
                ),
                if (collapsed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildAddTabButton(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// No cutout inset to add here, unlike `_Sidebar`: the landscape branch
  /// already wraps the whole row in a `SafeArea`, so the rail starts to the
  /// right of it and gets its full width. The width change is laid out at
  /// the width being animated to and clipped on the way, not reflowed at
  /// every intermediate width - a tab pill has no legible form at 100pt, so
  /// reflowing it would only produce an overflow stripe. Collapsed, there is
  /// no room to stand the back button and the toggle side by side, so they
  /// stack with the hamburger on top, where it is in the nav rail too.
  Widget _buildTabRailBody(bool collapsed) {
    final t = Translations.of(context);
    final borderColor = Theme.of(context).dividerColor;
    final barBackground = Theme.of(context).scaffoldBackgroundColor;
    final width = navRailWidth(collapsed);

    final backButton = _buildTabBarAction(
      key: const ValueKey('tabBarBackButton'),
      tooltip: t.common.back,
      icon: PhosphorIconsFill.arrowLeft,
      onTap: widget.onHide,
    );
    final toggle = NavRailToggleButton(collapsed: collapsed);

    return AnimatedContainer(
      duration: AppTheme.motionSlow,
      curve: AppTheme.interactiveCurve,
      width: width,
      decoration: BoxDecoration(
        color: barBackground,
        border: Border(right: BorderSide(color: borderColor)),
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
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
                  child: collapsed
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            toggle,
                            const SizedBox(height: 3),
                            backButton,
                          ],
                        )
                      : Row(children: [backButton, const Spacer(), toggle]),
                ),
                Expanded(
                  child: _buildTabList(
                    axis: Axis.vertical,
                    padding: const EdgeInsets.fromLTRB(3, 3, 3, 3),
                    stretch: !collapsed,
                    collapsed: collapsed,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 6),
                  child: Align(
                    alignment: collapsed
                        ? Alignment.center
                        : Alignment.centerLeft,
                    child: !_terminalLive()
                        ? _buildAddTabButton()
                        : collapsed
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildQuickSettingsButton(),
                              const SizedBox(height: 3),
                              _buildAddTabButton(),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildAddTabButton(),
                              const SizedBox(width: 6),
                              _buildQuickSettingsButton(),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A persistent tab is a named session first and a machine second: the
  /// name is what tells two shells on the same host apart, so it leads and
  /// the machine trails it after a dash. Without one there is nothing to
  /// lead with, and the machine's name is the whole label as before.
  Widget _buildTab(int i, {bool stretch = false, bool collapsed = false}) {
    final isActive = i == _activeIndex;
    final session = _sessions[i];
    final state = ref.watch(sshConnectionProvider(session));
    final displayName = ref.watch(anonymizeProvider)
        ? IdentityAnonymizer.name(session.$2.id)
        : session.$2.name;
    final sessionName = state.multiplexer.isPersistent
        ? _manager.muxNameFor(session.$1)
        : null;
    return TerminalTabPill<_TabConnectionAction>(
      key: _tabKeys[session.$1],
      sessionId: session.$1,
      profile: session.$2,
      status: state.status,
      sessionName: sessionName,
      displayName: displayName,
      mode: _modeFor(session.$1),
      isActive: isActive,
      stretch: stretch,
      collapsed: collapsed,
      menuItems: _buildTabMenuItems(session, state),
      onTap: () => _onTabTapped(session.$1),
      onMenuAction: (action) => _onTabAction(session, state, action),
    );
  }

  /// The strip's tabs, in the top bar or down the rail. One item per entry,
  /// so a split is picked up and moved as one.
  /// The whole tab is the drag handle rather than the default one, which a
  /// desktop gets over the tab's trailing edge - where its ⋮ menu is, so the
  /// menu could not be clicked. A drag past the slop moves the tab, a click
  /// still clicks, and a phone keeps the long press it always had.
  Widget _buildTabList({
    required Axis axis,
    required EdgeInsets padding,
    bool stretch = false,
    bool collapsed = false,
  }) {
    final entries = _entries;
    return ReorderableListView.builder(
      key: const ValueKey('sessionTabScroll'),
      scrollController: _tabScrollController,
      scrollDirection: axis,
      padding: padding,
      proxyDecorator: tabDragProxyDecorator,
      onReorderStart: (_) => HapticFeedback.selectionClick(),
      onReorderItem: _handleReorder,
      buildDefaultDragHandles: false,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final gap = i == entries.length - 1 ? 0.0 : 3.0;
        final entry = entries[i];
        return Padding(
          key: ValueKey('sessionTabItem-${entry.first}'),
          padding: axis == Axis.horizontal
              ? EdgeInsets.only(right: gap)
              : EdgeInsets.only(bottom: gap),
          child: ReorderDragListener(
            index: i,
            child: entry.length == 1
                ? _buildTab(
                    _sessions.indexWhere((s) => s.$1 == entry.first),
                    stretch: stretch,
                    collapsed: collapsed,
                  )
                : _buildSplitTab(
                    entry,
                    axis: axis,
                    stretch: stretch,
                    collapsed: collapsed,
                  ),
          ),
        );
      },
    );
  }

  /// A split's two tabs inside one frame, so the strip reads it as one entry.
  ///
  /// Padded along the strip only, and the border painted over rather than
  /// around: a split is exactly as tall as the tabs beside it. Across a
  /// horizontal strip every tab is stretched to its height, so the halves
  /// are too - centred, they came out shorter than the tabs beside them and
  /// the frame read as the taller one.
  Widget _buildSplitTab(
    List<String> entry, {
    required Axis axis,
    required bool stretch,
    required bool collapsed,
  }) {
    final focused = entry.contains(_sessions[_activeIndex].$1);
    final vertical = axis == Axis.vertical;
    final radius = BorderRadius.circular(AppTheme.radiusSm);
    return Container(
      key: ValueKey('splitTab-${entry.first}'),
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: context.colors.surfaceOffset,
        borderRadius: radius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: focused
              ? context.colors.primary.withValues(alpha: 0.5)
              : context.colors.surfaceBorder,
        ),
      ),
      child: Flex(
        direction: axis,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: !vertical || stretch
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        children: [
          for (final (i, id) in entry.indexed) ...[
            if (i > 0)
              SizedBox(width: vertical ? 0 : 2, height: vertical ? 2 : 0),
            _buildTab(
              _sessions.indexWhere((s) => s.$1 == id),
              stretch: stretch,
              collapsed: collapsed,
            ),
          ],
        ],
      ),
    );
  }

  void _onTabAction(
    (String, SshProfile) session,
    SshConnectionState state,
    _TabConnectionAction action,
  ) {
    switch (action) {
      case _TabConnectionAction.updateAgent:
        unawaited(_updateAgent(session.$2));
      case _TabConnectionAction.manageTunnels:
        _showTunnelsSheet(session.$1);
      case _TabConnectionAction.viewLog:
        unawaited(showConnectionLogSheet(context, session));
      case _TabConnectionAction.splitWith:
        unawaited(_showSplitPicker(session.$1));
      case _TabConnectionAction.unsplit:
        _unsplit(session.$1);
      case _TabConnectionAction.rename:
        _renameSession(session, state);
      case _TabConnectionAction.close:
        _closeSession(session.$1);
      case _TabConnectionAction.endSession:
        _endSession(session.$1);
      case _TabConnectionAction.reconnect:
        ref.read(sshConnectionProvider(session).notifier).connect();
    }
  }

  /// The header names a persistent session by its own name, the one that
  /// tells two shells on the same machine apart, and falls back to the
  /// machine's name otherwise. The view-mode row mirrors the badge beside
  /// the menu, laid out as one row so both sides are visible at once - the
  /// badge alone only ever shows where the tab is, not what the other
  /// option was called. Leaving comes last, one above the other as in
  /// earlier versions: detaching stands out, ending is only red text.
  List<DropdownItem<_TabConnectionAction>> _buildTabMenuItems(
    (String, SshProfile) session,
    SshConnectionState state,
  ) {
    final t = Translations.of(context);
    final colors = context.colors;
    final profile = session.$2;
    final connected = state.status == ConnectionStatus.connected;
    final persistent = state.multiplexer.isPersistent;

    DropdownItem<_TabConnectionAction> entry(
      _TabConnectionAction action,
      IconData icon,
      String label, {
      bool enabled = true,
      Color? color,
      Widget? trailing,
    }) => DropdownItem(
      key: ValueKey('tabMenuItem-${session.$1}-${action.name}'),
      value: action,
      intrinsicHeight: true,
      enabled: enabled,
      child: AppDropdownItem(
        icon: icon,
        label: label,
        color: color,
        trailing: trailing,
      ),
    );

    final anonymize = ref.read(anonymizeProvider);
    final header = DropdownItem<_TabConnectionAction>(
      key: ValueKey('tabMenuHeader-${session.$1}'),
      height: 56,
      enabled: false,
      child: TabMenuHeader(
        profile: profile,
        name: switch (persistent
            ? ref.read(sshSessionManagerProvider).muxNameFor(session.$1)
            : null) {
          final muxName? => SessionTab.displayName(muxName),
          null when anonymize => IdentityAnonymizer.name(profile.id),
          null => profile.name,
        },
        address: anonymize
            ? '${IdentityAnonymizer.username(profile.id)}@'
                  '${IdentityAnonymizer.host(profile.id)}'
            : '${profile.username}@${profile.host}',
        quality: connected
            ? _manager.getSession(session.$1)?.sshService?.quality
            : null,
      ),
    );

    final modes = DropdownItem<_TabConnectionAction>(
      key: ValueKey('viewModeSegments-${session.$1}'),
      height: 52,
      enabled: false,
      child: Padding(
        padding: const EdgeInsets.only(top: AppTheme.spaceXs),
        child: ViewModeSegments(
          sessionId: session.$1,
          mode: _modeFor(session.$1),
          onSelect: (picked) => _setMode(session.$1, picked),
        ),
      ),
    );

    final updateAvailable =
        _manager.agentStatusFor(profile.id)?.updateAvailable == true;
    final updating = _updatingAgentProfiles.contains(profile.id);
    final activeTunnels = connected
        ? ref
              .watch(portForwardingProvider(session.$1))
              .entries
              .values
              .where((entry) => entry.status == TunnelStatus.active)
              .length
        : 0;
    final actions = [
      if (updateAvailable)
        entry(
          _TabConnectionAction.updateAgent,
          PhosphorIconsRegular.downloadSimple,
          updating ? t.session.agentUpdating : t.session.agentUpdateTooltip,
          enabled: !updating,
          color: colors.primary,
        ),
      if (!connected &&
          (state.status == ConnectionStatus.disconnected ||
              state.status == ConnectionStatus.error))
        entry(
          _TabConnectionAction.reconnect,
          PhosphorIconsRegular.arrowClockwise,
          t.common.retry,
        ),
      if (_controller.isSplit(session.$1))
        entry(
          _TabConnectionAction.unsplit,
          PhosphorIconsRegular.arrowSquareOut,
          t.terminal.unsplit,
        )
      else
        entry(
          _TabConnectionAction.splitWith,
          PhosphorIconsRegular.squareSplitHorizontal,
          t.terminal.splitWith,
        ),
      if (connected)
        entry(
          _TabConnectionAction.manageTunnels,
          PhosphorIconsRegular.arrowsLeftRight,
          t.portForwarding.manageTunnels,
          trailing: activeTunnels > 0 ? CountBadge(activeTunnels) : null,
        ),
      if (persistent)
        entry(
          _TabConnectionAction.rename,
          PhosphorIconsRegular.pencilSimple,
          t.session.rename,
        ),
      entry(
        _TabConnectionAction.viewLog,
        PhosphorIconsRegular.listBullets,
        t.connection.viewLog,
      ),
    ];

    final leave = DropdownItem<_TabConnectionAction>(
      key: ValueKey('tabMenuLeave-${session.$1}'),
      height: persistent ? 112 : 60,
      enabled: false,
      child: TabMenuLeave(
        sessionId: session.$1,
        closeLabel: persistent
            ? t.session.detach
            : (connected ? t.terminal.disconnect : t.common.close),
        closeIcon: persistent
            ? PhosphorIconsRegular.arrowLineDown
            : PhosphorIconsRegular.x,
        endLabel: persistent ? t.session.endSession : null,
        onClose: () => _onTabAction(session, state, _TabConnectionAction.close),
        onEndSession: persistent
            ? () =>
                  _onTabAction(session, state, _TabConnectionAction.endSession)
            : null,
      ),
    );

    return [
      header,
      if (connected) modes,
      DropdownItem(
        key: ValueKey('tabMenuSection-${session.$1}'),
        height: 30,
        enabled: false,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            t.session.menuSection.toUpperCase(),
            style: colors.sectionLabel,
          ),
        ),
      ),
      ...actions,
      leave,
    ];
  }

  Widget _buildToolbarForActiveSession() {
    final sessionKey = _sessions[_activeIndex];
    final sessionState = _sessionKeys[sessionKey.$1]?.currentState;
    if (sessionState == null) return const SizedBox.shrink();
    final toolbarBackground = Theme.of(context).scaffoldBackgroundColor;
    final toolbarBorder = Theme.of(context).dividerColor;
    return ColoredBox(
      color: toolbarBackground,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: toolbarBorder),
          SpecialKeysToolbar(
            onKey: sessionState.writeRaw,
            ctrlNotifier: sessionState.ctrlMode,
            altNotifier: sessionState.altMode,
            shiftNotifier: sessionState.shiftMode,
            onDismissKeyboard: sessionState.blurTerminal,
            backgroundColor: toolbarBackground,
            borderColor: toolbarBorder,
            onRunSnippet: _runSnippetFromToolbar,
            snippetLabels: {
              for (final snippet in ref.watch(snippetsProvider))
                snippet.id: snippet.name,
            },
          ),
        ],
      ),
    );
  }

  /// Opens the toolbar layouts and the terminal's look over the session, so
  /// changing either does not mean a trip through Settings.
  Widget _buildQuickSettingsButton() {
    return _buildTabBarAction(
      key: const ValueKey('tabBarQuickSettingsButton'),
      tooltip: Translations.of(context).toolbar.quickSettings,
      icon: PhosphorIconsRegular.caretUp,
      onTap: _showQuickSettingsSheet,
    );
  }

  Future<void> _showQuickSettingsSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

    if (!mounted) return;
    await showSessionQuickSheet(
      context,
      showToolbarTab: _toolbarEnabled,
      snippetLabels: {
        for (final snippet in ref.read(snippetsProvider))
          snippet.id: snippet.name,
      },
      onManageToolbars: () => _pushSettingsScreen(
        t.settings.toolbarProfiles,
        const ToolbarProfilesScreen(),
      ),
      onOpenAppearance: () => _pushSettingsScreen(
        t.settings.terminalAppearance,
        const TerminalAppearanceScreen(),
      ),
    );
  }

  void _pushSettingsScreen(String title, Widget screen) {
    if (!mounted) return;
    unawaited(
      pushAppPage<void>(
        context,
        window: true,
        title: title,
        builder: (_) => screen,
      ),
    );
  }

  Widget _buildAddTabButton() {
    return _buildTabBarAction(
      key: const ValueKey('tabBarAddButton'),
      tooltip: Translations.of(context).terminal.selectDevice,
      icon: PhosphorIconsRegular.plus,
      onTap: _showAddSessionSheet,
    );
  }

  Widget _buildTabBarAction({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onTap,
  }) => StripActionButton(
    buttonKey: key,
    tooltip: tooltip,
    icon: icon,
    onTap: onTap,
  );

  /// Runs the snippet a toolbar slot is bound to. One that still needs
  /// argument values goes through the picker, which is where those get typed.
  Future<void> _runSnippetFromToolbar(String snippetId) async {
    final snippet = ref
        .read(snippetsProvider)
        .where((s) => s.id == snippetId)
        .firstOrNull;
    if (snippet == null) {
      AppNotifications.error(
        context,
        Translations.of(context).toolbar.snippetMissing,
      );
      return;
    }
    var values = const <String, String>{};
    if (snippet.placeholders.isNotEmpty) {
      final entered = await showSnippetArgsDialog(context, snippet);
      if (entered == null || !mounted) return;
      values = entered;
    }
    await _handleSnippetSelected(snippet, values);
  }

  /// Resolves [snippet]'s placeholders and runs it in the active session.
  /// Switches to the terminal view first so the result is visible.
  Future<void> _handleSnippetSelected(
    Snippet snippet,
    Map<String, String> argValues,
  ) async {
    if (_sessions.isEmpty) return;
    final sessionId = _sessions[_activeIndex].$1;
    final sessionState = _sessionKeys[sessionId]?.currentState;
    if (sessionState == null) return;

    _setMode(sessionId, SessionViewMode.terminal);
    sessionState.focusTerminal();

    final manager = ref.read(sshSessionManagerProvider);
    try {
      await launchSnippet(
        manager: manager,
        sessionId: sessionId,
        command: snippet.interpolate(argValues),
        shellType:
            manager.getSession(sessionId)?.remoteShellType ??
            RemoteShellType.unix,
      );
    } catch (error) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        Translations.of(
          context,
        ).snippets.runStageFailed(error: error.toString()),
      );
    }
  }

  Future<void> _updateAgent(SshProfile profile) async {
    if (_updatingAgentProfiles.contains(profile.id)) return;
    setState(() => _updatingAgentProfiles.add(profile.id));
    final t = Translations.of(context);
    try {
      final status = await _manager.updateAgent(profile);
      if (!mounted) return;
      AppNotifications.success(
        context,
        t.session.agentUpdated(version: status.remoteVersion ?? ''),
      );
    } catch (error) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        t.session.agentUpdateFailed(
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingAgentProfiles.remove(profile.id));
      }
    }
  }

  /// Whether the active tab is a terminal with a connection behind it.
  ///
  /// Two conditions hang off this, not one: the dock and the toolbar are
  /// shown over the same live terminal, but each has its own switch, so a
  /// toolbar turned off must not take the dock with it. A reconnect keeps the
  /// terminal on screen, and them with it: taking the toolbar away resizes the
  /// pane.
  bool _terminalLive() {
    final state = ref.watch(sshConnectionProvider(_sessions[_activeIndex]));
    return _activeMode == SessionViewMode.terminal &&
        (state.status == ConnectionStatus.connected ||
            state.status == ConnectionStatus.reconnecting);
  }

  /// A desktop has the keys and the pointer the toolbar and the floating
  /// dock stand in for; the settings stay what they are for the day the same
  /// backup lands on a phone.
  bool get _touchControls => platformHas(PlatformFeature.touchControls);

  bool _toolbarShown() => _terminalLive() && _toolbarEnabled && _touchControls;

  /// The dock's actions as a toolbar along the top on a desktop - the same
  /// switch turns it on and off, and the same editor picks what is on it.
  bool _actionBarShown() =>
      _terminalLive() && _floatingDockEnabled && !_touchControls;

  @override
  Widget build(BuildContext context) {
    if (_sessions.isEmpty) return const SizedBox.shrink();

    final activeKey = _sessions[_activeIndex];
    final terminalLive = _terminalLive();
    final showToolbar = _toolbarShown();
    final showActionBar = _actionBarShown();
    final tabsAtBottom =
        _tabBarPosition == TabBarPosition.bottom && !isWideLayout(context);
    final sessionViews = {
      for (int i = 0; i < _sessions.length; i++)
        _sessions[i].$1: SessionView(
          key: _sessionKeys[_sessions[i].$1],
          sessionKey: _sessions[i],
          viewMode: _modeFor(_sessions[i].$1),
          isActive: i == _activeIndex,
          sftpKey: _sftpKeys[_sessions[i].$1],
          onClose: () => _closeSession(_sessions[i].$1),
        ),
    };
    final entries = _entries;
    final activeEntry = _activeEntryIndex;

    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    final contentStack = Column(
      children: [
        if (showActionBar) _buildDesktopActionBar(activeKey),
        Expanded(
          child: Stack(
            children: [
              Listener(
                key: const ValueKey('sessionSwipeArea'),
                behavior: HitTestBehavior.translucent,
                onPointerDown: _swipe.onPointerDown,
                onPointerMove: _swipe.onPointerMove,
                onPointerUp: _swipe.onPointerUp,
                onPointerCancel: (_) => _swipe.cancel(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _swipe.viewportWidth = constraints.maxWidth;
                    return ValueListenableBuilder<double>(
                      valueListenable: _swipe.offset,
                      builder: (context, offset, _) {
                        return ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              for (int i = 0; i < entries.length; i++)
                                _buildSwipeSessionPage(
                                  index: i,
                                  activeIndex: activeEntry,
                                  offset: offset,
                                  width: constraints.maxWidth,
                                  child: entries[i].length == 1
                                      ? sessionViews[entries[i].first]!
                                      : _buildSplitEntry(
                                          entries[i],
                                          sessionViews,
                                        ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (terminalLive && _floatingDockEnabled && _touchControls)
                FloatingActionDock(
                  buttonKey: _dockButtonKey,
                  onTap: () => _openActionDock(activeKey),
                ),
            ],
          ),
        ),
        if (tabsAtBottom) _buildTabBar(atBottom: true),
        if (showToolbar)
          ColoredBox(
            color: backgroundColor,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildToolbarForActiveSession(),
            ),
          ),
      ],
    );

    if (isWideLayout(context)) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Row(
            children: [
              _buildTabRail(),
              Expanded(child: contentStack),
            ],
          ),
        ),
      );
    }

    if (tabsAtBottom) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(child: contentStack),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        automaticallyImplyLeading: false,
        toolbarHeight: terminalTabBarHeight(context),
        titleSpacing: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide.none),
        surfaceTintColor: backgroundColor.invisible,
        title: _buildTabBar(),
      ),
      body: SafeArea(top: false, child: contentStack),
    );
  }

  /// Lays `entry`'s two sessions over each other - the mechanics (fold on
  /// keyboard, divider drag, header swap) live in [SplitTabLayout]; this just
  /// wires it to the screen's own session state. Keyed on the pair, not its
  /// order, so a swap keeps the pane heights a folded pane is laid out at.
  /// Focusing a pane while the keyboard is up lets the keyboard follow the
  /// focus instead of closing on the way.
  Widget _buildSplitEntry(List<String> entry, Map<String, Widget> views) {
    final first = entry.first;
    return SplitTabLayout(
      key: ValueKey('splitTabLayout-${(entry.toList()..sort()).join('|')}'),
      entry: entry,
      paneBuilder: (id) => views[id]!,
      ratioOfFirst: _controller.ratioOf(first),
      focusedId: _sessions[_activeIndex].$1,
      profileFor: (id) => _sessions.firstWhere((s) => s.$1 == id).$2,
      labelFor: (id) => _tabLabel(_sessions.firstWhere((s) => s.$1 == id)),
      onFocusPane: (id, {keyboardUp = false}) {
        _selectSession(id, haptic: false);
        if (!keyboardUp) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sessionKeys[id]?.currentState?.focusTerminal();
        });
      },
      onSwap: _swapPanes,
      onRatioChanged: (ratio) => _controller.setRatio(first, ratio),
      onDividerHeldChanged: (held) {
        _dividerHeld = held;
        if (!held) _persistSplits();
      },
    );
  }

  bool handleBack() {
    if (dismissActionDockMenu()) return true;
    if (_sessions.isEmpty) return false;
    final activeKey = _sessions[_activeIndex].$1;
    final mode = _modeFor(activeKey);
    if (mode == SessionViewMode.sftp) {
      final sftpState = _sftpKeys[activeKey]?.currentState;
      if (sftpState != null && sftpState.canGoBackHistory) {
        sftpState.goBackHistory();
        return true;
      }
    }
    if (mode != SessionViewMode.terminal) {
      _setMode(activeKey, SessionViewMode.terminal);
      return true;
    }
    return false;
  }

  void blurAll() {
    for (final key in _sessions) {
      _sessionKeys[key.$1]?.currentState?.pauseTerminal();
    }
  }

  /// Called when MainShell wants [sessionId] on screen and this strip is
  /// already mounted (the overlay was only hidden, not closed, so
  /// `initState` never re-ran and would otherwise be the only place that
  /// picks up a newly tapped session). Existing tabs - across every machine,
  /// not just this one - are never torn down for this: an already-open tab
  /// just gets selected (attaching it if it went offline while hidden), and
  /// one that isn't open yet gets added alongside the others.
  void openSession(String sessionId, SshProfile profile) =>
      _attachTab(sessionId, profile);

  /// Picks a machine for a new tab, as the strip's + does. This and the
  /// methods after it are what the desktop's shortcuts and menus run: each is
  /// what the strip's own controls already do, under a name `MainShell` can
  /// call.
  void newSession() => unawaited(_showAddSessionSheet());

  /// Closes the tab on screen, leaving its session running on the server -
  /// what the tab's own close does.
  void closeActiveTab() {
    if (_sessions.isEmpty) return;
    unawaited(_closeSession(_sessions[_activeIndex].$1));
  }

  /// Moves [delta] tabs along the strip, wrapping at either end.
  void selectRelativeTab(int delta) {
    if (_sessions.length < 2) return;
    final next = (_activeIndex + delta) % _sessions.length;
    _selectSession(_sessions[next].$1, haptic: false);
    focusActiveTerminal();
  }

  /// The [index]th tab, counted from one end of the strip as the digit keys
  /// count; past the last tab is the last tab, as in a browser.
  void selectTabAt(int index) {
    if (_sessions.isEmpty) return;
    final at = math.min(index, _sessions.length - 1);
    _selectSession(_sessions[at].$1, haptic: false);
    focusActiveTerminal();
  }

  /// Opens the search bar over the session on screen.
  void findInActiveSession() {
    if (_sessions.isEmpty) return;
    _sessionKeys[_sessions[_activeIndex].$1]?.currentState?.openSearch();
  }

  /// Picks a file and uploads it into the session on screen, as the dock's
  /// Fast upload does.
  void uploadToActiveSession() {
    if (_sessions.isEmpty) return;
    final session = _sessionKeys[_sessions[_activeIndex].$1]?.currentState;
    if (session != null) unawaited(session.uploadFileToTerminal());
  }

  /// Puts the keyboard on the session on screen. On a phone that would
  /// raise the soft keyboard, which only a tap may do; a desktop has nothing
  /// to raise, and a session that needs a click before it takes keys is a
  /// session that ate the first one.
  void focusActiveTerminal() {
    if (!isDesktopPlatform || _sessions.isEmpty) return;
    final id = _sessions[_activeIndex].$1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sessionKeys[id]?.currentState?.focusTerminal();
    });
  }
}

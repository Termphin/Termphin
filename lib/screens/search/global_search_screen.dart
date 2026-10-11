import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/profile_group.dart';
import '../../models/session_tab.dart';
import '../../models/snippet.dart';
import '../../models/ssh_key.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../providers/terminal_overlay_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/search/global_search.dart';
import '../../services/ssh/ssh_session_manager.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/platform_info.dart';
import '../../widgets/profiles/profile_avatar.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/app_sheet.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/group_dot.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';
import '../../widgets/ui/section_navigator.dart';
import '../keys/key_form_screen.dart';
import '../snippets/snippet_run_screen.dart';
import '../snippets/snippet_runs_screen.dart';
import 'global_search_launcher.dart';

/// One search over everything: machines (name, address, username), their
/// sessions, groups, snippets and keys. Opened from the box at the top of
/// each main screen, which flies up to become this screen's field.
///
/// A tap does what it does on the item's own screen - a machine connects,
/// a session opens, a snippet runs, a key opens for editing. A group does
/// not leave: it narrows the search to itself, shown as a chip under the
/// field. Enter takes the best match.
///
/// With [onPick] it only picks a machine out of [pickFrom] - the new-session
/// sheet opens it that way: no sessions, groups, snippets or keys, every
/// machine listed while nothing is typed, and a tap hands the machine back
/// instead of opening it. [header] says what the pick is for.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({
    super.key,
    required this.heroTag,
    this.hint,
    this.pickFrom,
    this.onPick,
    this.header,
  });

  final Object heroTag;
  final String? hint;
  final List<SshProfile>? pickFrom;
  final ValueChanged<SshProfile>? onPick;
  final Widget? header;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  late final SshSessionManager _manager = ref.read(sshSessionManagerProvider);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  ProfileGroup? _scope;
  List<SshKey> _keys = const [];
  Animation<double>? _routeAnimation;

  /// Every result in the order drawn, and the one of them Enter opens -
  /// moved with the arrow keys, back to the top whenever the list changes.
  List<Object> _items = const [];
  int _cursor = 0;
  final _cursorKey = GlobalKey();

  /// A phone's soft keyboard has no arrows, so the cursor is only drawn on a
  /// desktop or once a hardware keyboard has moved it.
  bool _arrowed = false;

  /// Set when a result takes the user to the terminal. The box then does not
  /// fly back to the list: the list is not what they are looking at.
  bool _leavingForTerminal = false;

  bool get _picking => widget.onPick != null;

  @override
  void initState() {
    super.initState();
    if (!_picking) unawaited(_loadKeys());
  }

  /// Waits for the route's hero flight to land before opening the keyboard:
  /// opening it mid-flight resizes the page under the hero and the flight
  /// ends somewhere else. The animation is read after the first frame, since
  /// before the route is installed it is a stand-in that already reads as
  /// completed.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeAnimation != null) return;
    final animation = ModalRoute.of(context)?.animation;
    _routeAnimation = animation;
    if (animation == null) {
      _focusNode.requestFocus();
      return;
    }
    animation.addStatusListener(_focusWhenLanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && animation.isCompleted) {
        _focusWhenLanded(AnimationStatus.completed);
      }
    });
  }

  /// Requests focus one frame after the hero flight lands: the field only
  /// exists from the frame after the flight, since until then the hero holds
  /// an empty placeholder where it goes.
  void _focusWhenLanded(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_focusWhenLanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_focusWhenLanded);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    final keys = await ref.read(sshKeyStorageProvider).loadKeys();
    if (mounted) setState(() => _keys = keys);
  }

  void _setQuery(String value) => setState(() {
    _query = value;
    _cursor = 0;
  });

  void _clear() {
    _controller.clear();
    _setQuery('');
    _focusNode.requestFocus();
  }

  void _enterGroup(ProfileGroup group) {
    _controller.clear();
    setState(() {
      _query = '';
      _scope = group;
      _cursor = 0;
    });
    _focusNode.requestFocus();
  }

  void _leaveGroup() {
    setState(() {
      _scope = null;
      _cursor = 0;
    });
    _focusNode.requestFocus();
  }

  void _openMachine(SshProfile profile) {
    if (_picking) {
      _leaveForTerminal();
      widget.onPick!(profile);
      return;
    }
    final overlay = ref.read(terminalOverlayProvider.notifier);
    _leaveForTerminal();
    overlay.openProfile(profile);
  }

  void _openSession(ActiveSessionView session) {
    final overlay = ref.read(terminalOverlayProvider.notifier);
    _leaveForTerminal();
    overlay.show(session.id, session.profile, scope: SiblingScope.none);
  }

  /// Heroes are paired on the frame after the pop, so turning this one off
  /// in the same call is in time to keep it on the ground.
  void _leaveForTerminal() {
    setState(() => _leavingForTerminal = true);
    Navigator.of(context).pop();
  }

  Future<void> _runSnippet(Snippet snippet) async {
    final batchId = await showSnippetRunScreen(context, snippet);
    if (batchId == null || !mounted) return;
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.snippetRuns));
    await pushAppPage<void>(
      context,
      window: true,
      title: Translations.of(context).snippets.runsTitle,
      builder: (_) => const SnippetRunsScreen(),
    );
  }

  Future<void> _editKey(SshKey key) async {
    await showKeyFormScreen(context, existing: key);
    if (!mounted) return;
    ref.read(sshKeysRevisionProvider.notifier).bump();
    await _loadKeys();
  }

  int get _selected => math.min(_cursor, _items.length - 1);

  void _openSelected() {
    if (_items.isNotEmpty) _open(_items[_selected]);
  }

  /// Up and down move the cursor through the results while the field keeps
  /// the focus, so typing and picking never take turns.
  KeyEventResult _onFieldKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    if (_items.isEmpty) return KeyEventResult.handled;
    setState(() {
      _arrowed = true;
      _cursor = (_selected + step) % _items.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _cursorKey.currentContext;
      if (row == null || !row.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          row,
          duration: AppTheme.interactiveDuration,
          alignmentPolicy: step > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
    });
    return KeyEventResult.handled;
  }

  void _open(Object item) {
    switch (item) {
      case final SshProfile p:
        _openMachine(p);
      case final ActiveSessionView s:
        _openSession(s);
      case final GroupHit g:
        _enterGroup(g.group);
      case final Snippet s:
        unawaited(_runSnippet(s));
      case final SshKey k:
        unawaited(_editKey(k));
    }
  }

  /// Shown as a palette on a desktop, the screen has no back arrow: it is
  /// left with Esc or a click beside it, with nothing to go back from.
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final profiles = ref.watch(profilesProvider);
    final groups = ref.watch(profileGroupsProvider);
    final snippets = ref.watch(snippetsProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _manager,
          builder: (context, _) {
            final manager = _manager;
            final pool = widget.pickFrom ?? profiles;
            var results = globalSearch(
              query: _query,
              profiles: pool,
              groups: groups,
              sessions: _picking ? const [] : manager.tabs,
              snippets: _picking ? const [] : snippets,
              keys: _picking ? const [] : _keys,
              generalLabel: t.groups.general,
              scope: _scope?.name,
              recentLimit: _picking ? pool.length : 5,
            );
            if (_picking) {
              results = GlobalSearchResults(machines: results.machines);
            }
            _items = [
              for (final section in results.sections)
                ...results.itemsOf(section),
            ];
            final browsing = _query.trim().isEmpty && _scope == null;

            return ContentGutter(
              builder: (context, gutter) => Column(
                children: [
                  Padding(
                    padding: gutter.add(const EdgeInsets.fromLTRB(4, 8, 16, 8)),
                    child: Row(
                      children: [
                        if (!AppModalScope.isDialog(context))
                          IconButton(
                            tooltip: t.globalSearch.back,
                            icon: const Icon(PhosphorIconsRegular.arrowLeft),
                            color: colors.textSecondary,
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        else
                          const SizedBox(width: 12),
                        Expanded(child: _field(t, results)),
                      ],
                    ),
                  ),
                  if (widget.header case final header?)
                    Padding(
                      padding: gutter.add(
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      ),
                      child: header,
                    ),
                  if (_scope != null)
                    Padding(
                      padding: gutter.add(
                        const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _ScopeChip(
                          group: _scope!,
                          label: t.globalSearch.inGroup(
                            group: _groupLabel(t, _scope!.name),
                          ),
                          tooltip: t.globalSearch.leaveGroup,
                          onClear: _leaveGroup,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _Entrance(
                      animation: _routeAnimation,
                      child: _results(t, results, browsing, gutter),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _field(Translations t, GlobalSearchResults results) {
    final colors = context.colors;
    return HeroMode(
      enabled: !_leavingForTerminal,
      child: Hero(
        tag: widget.heroTag,
        flightShuttleBuilder: searchBoxFlight(_hint(t)),
        child: SearchBox(
          focused: 1,
          child: Row(
            children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onFieldKey,
                  child: TextField(
                    key: const ValueKey('globalSearchField'),
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _setQuery,
                    onSubmitted: (_) => _openSelected(),
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TextStyle(
                      fontFamily: AppTheme.uiFamily,
                      fontSize: 15,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: _hint(t),
                      hintStyle: TextStyle(
                        fontFamily: AppTheme.uiFamily,
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: t.globalSearch.clear,
                  onPressed: _clear,
                  icon: Icon(
                    PhosphorIconsRegular.x,
                    size: 16,
                    color: colors.textTertiary,
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(
    Translations t,
    GlobalSearchResults results,
    bool browsing,
    EdgeInsets gutter,
  ) {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    final manager = _manager;
    final current = _items.isEmpty || !(isDesktopPlatform || _arrowed)
        ? null
        : _items[_selected];
    Widget row(Object item, Widget child) {
      final selected = identical(item, current);
      return _Cursor(
        key: selected ? _cursorKey : null,
        selected: selected,
        child: child,
      );
    }

    Widget? section(SearchSection kind) => switch (kind) {
      SearchSection.sessions when results.sessions.isNotEmpty => _Section(
        title: browsing ? t.globalSearch.openSessions : t.globalSearch.sessions,
        children: [
          for (final s in results.sessions)
            row(
              s,
              _SessionResult(
                session: s,
                terms: terms,
                onTap: () => _openSession(s),
              ),
            ),
        ],
      ),
      SearchSection.machines when results.machines.isNotEmpty => _Section(
        title: browsing && !_picking
            ? t.globalSearch.recentMachines
            : t.globalSearch.machines,
        children: [
          for (final p in results.machines)
            row(
              p,
              _MachineResult(
                profile: p,
                groupLabel: _groupLabel(t, p.group),
                live: manager.getSessionsForProfile(p.id).isNotEmpty,
                terms: terms,
                onTap: () => _openMachine(p),
              ),
            ),
        ],
      ),
      SearchSection.groups when results.groups.isNotEmpty => _Section(
        title: t.globalSearch.groups,
        children: [
          for (final g in results.groups)
            row(
              g,
              _GroupResult(
                hit: g,
                label: _groupLabel(t, g.group.name),
                terms: terms,
                onTap: () => _enterGroup(g.group),
              ),
            ),
        ],
      ),
      SearchSection.snippets when results.snippets.isNotEmpty => _Section(
        title: t.globalSearch.snippets,
        children: [
          for (final s in results.snippets)
            row(
              s,
              _SnippetResult(
                snippet: s,
                terms: terms,
                onTap: () => _runSnippet(s),
              ),
            ),
        ],
      ),
      SearchSection.keys when results.keys.isNotEmpty => _Section(
        title: t.globalSearch.keys,
        children: [
          for (final k in results.keys)
            row(
              k,
              _KeyResult(
                sshKey: k,
                groupLabel: _groupLabel(t, k.group),
                terms: terms,
                onTap: () => _editKey(k),
              ),
            ),
        ],
      ),
      _ => null,
    };
    final sections = [for (final kind in results.sections) ?section(kind)];

    if (sections.isEmpty) {
      return ListView(
        padding: gutter,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          EmptyStateHint(
            icon: PhosphorIconsFill.magnifyingGlass,
            text: browsing
                ? (_picking ? t.terminal.noDevices : t.globalSearch.emptyHint)
                : t.globalSearch.noResults(query: _query.trim()),
          ),
        ],
      );
    }

    return ListView(
      padding: gutter.add(
        EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const SizedBox(height: 20),
          section,
        ],
        if (browsing && !_picking) ...[
          const SizedBox(height: 16),
          Text(
            t.globalSearch.emptyHint,
            style: context.colors.uiSmall.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  String _hint(Translations t) => widget.hint ?? t.globalSearch.hint;

  String _groupLabel(Translations t, String group) {
    final known = [for (final g in ref.read(profileGroupsProvider)) g.name];
    final resolved =
        resolveGroupName(group, known) ?? GroupStorage.defaultGroup;
    return isSameGroup(resolved, GroupStorage.defaultGroup)
        ? t.groups.general
        : resolved;
  }
}

/// Results rise into place once the box has landed, rather than sliding up
/// with the page under a hero that is still in the air.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.animation, required this.child});

  final Animation<double>? animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parent = animation;
    if (parent == null) return child;
    final curved = CurvedAnimation(
      parent: parent,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: SectionHeader(title),
        ),
        AppCard.fields(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const AppDivider(indent: 64),
              child,
            ],
          ],
        ),
      ],
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.group,
    required this.label,
    required this.tooltip,
    required this.onClear,
  });

  final ProfileGroup group;
  final String label;
  final String tooltip;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('globalSearchScope'),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: colors.primaryHighlight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: colors.primaryMuted),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupDot(colorHex: group.colorHex, size: 8),
          const SizedBox(width: 8),
          Text(
            label,
            style: context.colors.uiStyle.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            tooltip: tooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: Icon(PhosphorIconsRegular.x, size: 14, color: colors.primary),
          ),
        ],
      ),
    );
  }
}

/// Marks the result row Enter opens, for [_ResultRow] to draw.
class _Cursor extends InheritedWidget {
  const _Cursor({super.key, required this.selected, required super.child});

  final bool selected;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Cursor>()?.selected ?? false;

  @override
  bool updateShouldNotify(_Cursor old) => selected != old.selected;
}

/// One row of results: something round on the left, a title with the typed
/// words picked out, a line under it, and an optional trailing hint.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.terms,
    required this.onTap,
    this.trailing,
    this.subtitleMono = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final List<String> terms;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool subtitleMono;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitleStyle = (subtitleMono ? colors.monoSmall : colors.uiSmall)
        .copyWith(color: colors.textTertiary);
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.interactiveDuration,
        color: _Cursor.of(context)
            ? colors.primaryHighlight
            : colors.primaryHighlight.invisible,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            SizedBox(width: 36, child: Center(child: leading)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    _highlighted(
                      title,
                      terms,
                      colors.itemTitle.copyWith(fontSize: 15),
                      colors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      _highlighted(
                        subtitle,
                        terms,
                        subtitleStyle,
                        colors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// [text] with every occurrence of a typed word drawn in [accent].
TextSpan _highlighted(
  String text,
  List<String> terms,
  TextStyle style,
  Color accent,
) {
  if (terms.isEmpty || text.isEmpty) return TextSpan(text: text, style: style);
  final lower = text.toLowerCase();
  final marked = List<bool>.filled(text.length, false);
  for (final term in terms) {
    var from = 0;
    while (true) {
      final at = lower.indexOf(term, from);
      if (at < 0) break;
      for (var i = at; i < at + term.length && i < text.length; i++) {
        marked[i] = true;
      }
      from = at + term.length;
    }
  }
  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marked[i] != marked[start]) {
      spans.add(
        TextSpan(
          text: text.substring(start, i),
          style: marked[start]
              ? style.copyWith(color: accent, fontWeight: FontWeight.w700)
              : null,
        ),
      );
      start = i;
    }
  }
  return TextSpan(style: style, children: spans);
}

class _MachineResult extends ConsumerWidget {
  const _MachineResult({
    required this.profile,
    required this.groupLabel,
    required this.live,
    required this.terms,
    required this.onTap,
  });

  final SshProfile profile;
  final String groupLabel;
  final bool live;
  final List<String> terms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anonymize = ref.watch(anonymizeProvider);
    final name = anonymize ? IdentityAnonymizer.name(profile.id) : profile.name;
    final user = anonymize
        ? IdentityAnonymizer.username(profile.id)
        : profile.username;
    final host = anonymize ? IdentityAnonymizer.host(profile.id) : profile.host;
    return _ResultRow(
      leading: ProfileAvatar(
        iconName: profile.iconName,
        colorHex: profile.colorHex,
        isActive: live,
        size: 36,
      ),
      title: name,
      subtitle: '$user@$host:${profile.port} · $groupLabel',
      terms: terms,
      onTap: onTap,
      trailing: Icon(
        PhosphorIconsRegular.caretRight,
        size: 16,
        color: context.colors.textTertiary,
      ),
    );
  }
}

class _SessionResult extends ConsumerWidget {
  const _SessionResult({
    required this.session,
    required this.terms,
    required this.onTap,
  });

  final ActiveSessionView session;
  final List<String> terms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final anonymize = ref.watch(anonymizeProvider);
    final profile = session.profile;
    final machine = anonymize
        ? IdentityAnonymizer.name(profile.id)
        : profile.name;
    final address = anonymize
        ? '${IdentityAnonymizer.username(profile.id)}@${IdentityAnonymizer.host(profile.id)}'
        : '${profile.username}@${profile.host}';
    final muxName = session.muxName;
    final connecting = session.connecting && !session.dropped;
    final connected = !session.dropped && !connecting;
    final resumable = session.multiplexer.isPersistent;
    final accent = connecting
        ? colors.primary
        : connected
        ? colors.success
        : resumable
        ? colors.warning
        : colors.textTertiary;

    return _ResultRow(
      leading: _IconAvatar(
        icon: PhosphorIconsRegular.terminalWindow,
        color: accent,
      ),
      title: muxName != null ? SessionTab.displayName(muxName) : address,
      subtitle: muxName != null ? '$machine · $address' : machine,
      terms: terms,
      onTap: onTap,
      trailing: Text(
        connecting
            ? t.connection.connecting
            : connected
            ? session.uptimeFormatted
            : resumable
            ? t.session.detached
            : t.connection.disconnected,
        style: colors.uiSmall.copyWith(
          color: accent,
          fontWeight: connected ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _GroupResult extends StatelessWidget {
  const _GroupResult({
    required this.hit,
    required this.label,
    required this.terms,
    required this.onTap,
  });

  final GroupHit hit;
  final String label;
  final List<String> terms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final contents = [
      if (hit.machines > 0) t.globalSearch.machineCount(n: hit.machines),
      if (hit.snippets > 0) t.globalSearch.snippetCount(n: hit.snippets),
      if (hit.keys > 0) t.globalSearch.keyCount(n: hit.keys),
    ];
    return _ResultRow(
      leading: _IconAvatar(
        icon: PhosphorIconsRegular.folderSimple,
        color: hit.group.colorHex == null
            ? context.colors.textTertiary
            : ProfileAvatarColor.forHex(hit.group.colorHex).color,
      ),
      title: label,
      subtitle: contents.isEmpty
          ? t.globalSearch.emptyGroup
          : contents.join(' · '),
      terms: terms,
      onTap: onTap,
      trailing: Icon(
        PhosphorIconsRegular.funnelSimple,
        size: 16,
        color: context.colors.textTertiary,
      ),
    );
  }
}

class _SnippetResult extends StatelessWidget {
  const _SnippetResult({
    required this.snippet,
    required this.terms,
    required this.onTap,
  });

  final Snippet snippet;
  final List<String> terms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ResultRow(
      leading: _IconAvatar(
        icon: PhosphorIconsRegular.codeBlock,
        color: ProfileAvatarColor.colors.first.color,
      ),
      title: snippet.name,
      subtitle: snippet.command.split('\n').first,
      subtitleMono: true,
      terms: terms,
      onTap: onTap,
      trailing: Icon(
        PhosphorIconsRegular.play,
        size: 16,
        color: context.colors.textTertiary,
      ),
    );
  }
}

class _KeyResult extends StatelessWidget {
  const _KeyResult({
    required this.sshKey,
    required this.groupLabel,
    required this.terms,
    required this.onTap,
  });

  final SshKey sshKey;
  final String groupLabel;
  final List<String> terms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _ResultRow(
      leading: _IconAvatar(
        icon: PhosphorIconsRegular.key,
        color: ProfileAvatarColor.colors.first.color,
      ),
      title: sshKey.name,
      subtitle: '${sshKey.keyType.label} · $groupLabel',
      terms: terms,
      onTap: onTap,
      trailing: Icon(
        PhosphorIconsRegular.pencilSimple,
        size: 16,
        color: colors.textTertiary,
      ),
    );
  }
}

/// The leading glyph of anything that is not a machine: the icon alone, in
/// its colour. Only machines carry the round avatar, so they stay the ones
/// that read as places to connect to.
class _IconAvatar extends StatelessWidget {
  const _IconAvatar({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 22, color: color);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/snippets_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../../widgets/terminal/special_keys_toolbar.dart'
    show toolbarSchemeFromTheme;
import '../../widgets/terminal/toolbar_key_button.dart';
import '../../widgets/terminal/toolbar_key_picker_sheet.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/app_search_field.dart';
import '../../widgets/ui/app_sheet.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/section_header.dart';
import '../../widgets/ui/stepper_row.dart';
import '../../widgets/ui/tag_chip.dart';

enum _ScreenAction { grid, reset }

/// Gap between slots, matching the live toolbar's own spacing.
const _kSlotGap = 4.0;

/// The special-keys toolbar's editor: which key sits in which slot, how the
/// grid is shaped, and the pool of everything that can go in it.
///
/// Edits the profile named by [profileId] rather than whatever the toolbar
/// happens to be drawing, so opening a layout does not hand the toolbar to it.
///
/// Laid out as a fixed grid over a scrolling pool. Both halves have to be on
/// screen together: a key is placed by tapping a slot and then a key (or by
/// dragging one onto it), and neither gesture can reach across a scroll that
/// has pushed the grid out of sight.
///
/// **One gesture means one thing.** Any slot - filled or empty - selects on a
/// tap, and what can be done with the selection lives in a bar under the grid.
/// Filled slots used to raise their own menu instead, so the same tap on two
/// things that look alike did two different jobs, and the menu's "replace"
/// only put you into the mode an empty slot was already in.
class ToolbarSettingsScreen extends ConsumerStatefulWidget {
  const ToolbarSettingsScreen({super.key, required this.profileId});

  final String profileId;

  @override
  ConsumerState<ToolbarSettingsScreen> createState() =>
      _ToolbarSettingsScreenState();
}

/// Reset sits behind the app bar's action dropdown rather than as a bare
/// text button, since it is the one action that throws away the whole
/// layout and does not belong in the easiest place to hit. The grid and the
/// pool below it share one width, worked out the way the grid itself lays
/// out, and the grid stays pinned above the scrolling pool - never scrolling
/// away from the keys that fill it - so a tap-then-tap or a drag always has
/// both ends in view.
class _ToolbarSettingsScreenState extends ConsumerState<ToolbarSettingsScreen> {
  /// The layout being edited.
  ///
  /// A notifier rather than a plain field because the grid sheet is its own
  /// route: this screen's `setState` does not reach into it, so every stepper
  /// in it would read a value frozen at the moment it opened.
  final _layoutNotifier = ValueNotifier(ToolbarLayout.defaults);
  ToolbarLayout get _layout => _layoutNotifier.value;

  String _poolQuery = '';
  bool _loading = true;
  int _page = 0;

  /// Slot the next tapped key drops into. Null means "first free slot".
  ///
  /// Survives a page change on purpose: clearing it there made moving a key
  /// from one page to another impossible.
  int? _selectedSlot;

  final _searchController = TextEditingController();

  /// Listens for the stored profiles and custom keys too, since both can
  /// also change from the custom key editor, which writes them directly.
  @override
  void initState() {
    super.initState();
    unawaited(
      AnalyticsService.instance.screen(AnalyticsScreen.toolbarSettings),
    );
    _layoutNotifier.addListener(_onLayoutChanged);
    toolbarSettings.profiles.addListener(_onStoredLayoutChanged);
    toolbarSettings.customKeys.addListener(_onCustomKeysChanged);
    _load();
  }

  @override
  void dispose() {
    _layoutNotifier.removeListener(_onLayoutChanged);
    _layoutNotifier.dispose();
    toolbarSettings.profiles.removeListener(_onStoredLayoutChanged);
    toolbarSettings.customKeys.removeListener(_onCustomKeysChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLayoutChanged() {
    if (mounted) setState(() {});
  }

  void _onStoredLayoutChanged() {
    if (!mounted) return;
    _layoutNotifier.value = toolbarProfileLayout(widget.profileId);
  }

  void _onCustomKeysChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await toolbarSettings.profiles.load();
    await toolbarSettings.customKeys.load();
    if (!mounted) return;
    _layoutNotifier.value = toolbarProfileLayout(widget.profileId);
    setState(() => _loading = false);
  }

  String get _title {
    final profiles = toolbarSettings.profiles.value.profiles;
    final index = profiles.indexWhere(
      (profile) => profile.id == widget.profileId,
    );
    final name = index < 0 ? '' : profiles[index].name;
    return name.isEmpty
        ? Translations.of(context).settings.toolbarProfileDefault
        : name;
  }

  Future<void> _applyLayout(ToolbarLayout next) async {
    final normalized = next.copyWith(
      order: normalizeToolbarOrder(next.order, slotCount: next.slotCount),
    );
    _layoutNotifier.value = normalized;
    setState(() {
      if (_page >= normalized.pages) _page = normalized.pages - 1;
      if (_selectedSlot != null && _selectedSlot! >= normalized.slotCount) {
        _selectedSlot = null;
      }
    });
    await saveToolbarProfileLayout(widget.profileId, normalized);
  }

  Future<void> _applyOrder(List<String> order) =>
      _applyLayout(_layout.copyWith(order: order));

  /// Puts [previous] back, for the Undo on a destructive change.
  void _undoTo(ToolbarLayout previous) {
    setState(() => _selectedSlot = null);
    unawaited(_applyLayout(previous));
  }

  Future<void> _reset() async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.toolbarResetTitle,
      message: t.settings.toolbarResetMessage,
      confirmLabel: t.common.reset,
    );
    if (!confirmed || !mounted) return;
    final previous = _layout;
    setState(() => _selectedSlot = null);
    await _applyLayout(ToolbarLayout.defaults);
    if (!mounted) return;
    AppNotifications.success(
      context,
      t.settings.toolbarResetDone,
      actionLabel: t.common.undo,
      onAction: () => _undoTo(previous),
    );
  }

  /// Applies a grid change, asking first when it would cost keys.
  Future<void> _resize({int? columns, int? rows, int? pages}) async {
    final lost = _layout.keysLostByResize(
      columns: columns,
      rows: rows,
      pages: pages,
    );
    if (lost > 0) {
      final t = Translations.of(context);
      final confirmed = await showConfirmDialog(
        context,
        title: t.settings.toolbarResizeTitle,
        message: t.settings.toolbarResizeMessage(count: lost),
        confirmLabel: t.settings.toolbarResizeConfirm,
      );
      if (!confirmed) return;
    }
    await _applyLayout(
      _layout.resized(columns: columns, rows: rows, pages: pages),
    );
  }

  Set<String> get _usedIds =>
      _layout.order.where((id) => id.isNotEmpty).toSet();

  int _slotIndex(int indexOnPage) => _page * _layout.slotsPerPage + indexOnPage;

  String _idAt(int slot) =>
      slot >= 0 && slot < _layout.order.length ? _layout.order[slot] : '';

  /// Which page a key currently sits on, or null when it is unplaced.
  int? _pageOf(String id) {
    final index = _layout.order.indexOf(id);
    if (index < 0) return null;
    return index ~/ _layout.slotsPerPage;
  }

  /// The same key twice would be two buttons doing one thing, so placing a
  /// key already on the toolbar leaves its old slot empty rather than
  /// cloning it.
  Future<void> _placeInSlot(int slot, String id) async {
    final next = List<String>.from(_layout.order);
    if (slot >= next.length) return;
    final existing = next.indexOf(id);
    if (existing >= 0) next[existing] = '';
    next[slot] = id;
    setState(() => _selectedSlot = null);
    await _applyOrder(next);
  }

  Future<void> _swapSlots(int a, int b) async {
    final next = List<String>.from(_layout.order);
    if (a >= next.length || b >= next.length) return;
    final held = next[a];
    next[a] = next[b];
    next[b] = held;
    await _applyOrder(next);
  }

  Future<void> _clearSlot(int slot) async {
    final id = _idAt(slot);
    if (id.isEmpty) return;
    final t = Translations.of(context);
    final previous = _layout;
    final next = List<String>.from(_layout.order);
    next[slot] = '';
    setState(() => _selectedSlot = null);
    await _applyOrder(next);
    if (!mounted) return;
    AppNotifications.success(
      context,
      t.settings.toolbarKeyRemoved(name: _labelForId(id)),
      actionLabel: t.common.undo,
      onAction: () => _undoTo(previous),
    );
  }

  /// A pool key was tapped: it fills the selected slot, or the first free
  /// one. A key already on the toolbar is not placed again - its page and
  /// slot are shown instead, rather than silently doing nothing.
  Future<void> _poolKeyTapped(String id) async {
    final selected = _selectedSlot;
    if (selected != null) {
      await _placeInSlot(selected, id);
      return;
    }
    final placedOn = _pageOf(id);
    if (placedOn != null) {
      setState(() {
        _page = placedOn;
        _selectedSlot = _layout.order.indexOf(id);
      });
      return;
    }
    final free = _layout.order.indexOf('');
    if (free == -1) {
      if (!mounted) return;
      AppNotifications.info(
        context,
        Translations.of(context).settings.toolbarNoFreeSlot,
      );
      return;
    }
    setState(() => _page = free ~/ _layout.slotsPerPage);
    await _placeInSlot(free, id);
  }

  Future<void> _addCustomKey() async {
    final id = await showCustomKeyEditor(context);
    if (id == null) return;
    await addToolbarCustomKey(id);
    if (!mounted) return;
    await _poolKeyTapped(id);
  }

  /// Edits a custom key in place: the library and every slot holding it move
  /// over together.
  Future<void> _editCustomKey(ToolbarAction action) async {
    final updated = await showCustomKeyEditor(context, initial: action);
    if (updated == null) return;
    await replaceToolbarCustomKey(action.id, updated);
    if (!mounted) return;
    _layoutNotifier.value = toolbarProfileLayout(widget.profileId);
  }

  String _labelForId(String id) {
    final action = toolbarActionForId(id);
    if (action == null) return '';
    if (action.kind == ToolbarActionKind.snippet) {
      final snippet = ref
          .read(snippetsProvider)
          .where((s) => s.id == action.payload)
          .firstOrNull;
      if (snippet != null) return shortToolbarLabel(snippet.name);
    }
    return shortToolbarLabel(action.label);
  }

  /// A slot was tapped.
  ///
  /// Selecting a slot that holds a key means picking that key up, so the next
  /// slot tapped is where it goes. That is the only way to move a key onto
  /// another page: a drag cannot reach a page that is not on screen, and the
  /// selection is kept across a page change for exactly this.
  ///
  /// A selected *empty* slot holds nothing, so tapping elsewhere only moves
  /// the selection.
  void _tapSlot(int slot) {
    final selected = _selectedSlot;
    if (selected == slot) {
      setState(() => _selectedSlot = null);
      return;
    }
    if (selected != null && _idAt(selected).isNotEmpty) {
      setState(() => _selectedSlot = slot);
      unawaited(_swapSlots(selected, slot));
      return;
    }
    setState(() => _selectedSlot = slot);
  }

  /// The grid, drawn at the width the real toolbar would draw it.
  Widget _buildGrid(TerminalColorScheme scheme, double slotWidth) {
    final ids = _layout.pageIds(_page);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int row = 0; row < _layout.rows; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : _kSlotGap),
            child: Row(
              children: [
                for (int column = 0; column < _layout.columns; column++) ...[
                  if (column > 0) const SizedBox(width: _kSlotGap),
                  Expanded(
                    child: _buildSlot(
                      row * _layout.columns + column,
                      ids,
                      scheme,
                      slotWidth,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// A filled slot is dragged with a long press, not a plain drag: a grid of
  /// keys under a thumb that is also scrolling the pool below would
  /// otherwise rearrange itself by accident.
  Widget _buildSlot(
    int indexOnPage,
    List<String> pageIds,
    TerminalColorScheme scheme,
    double slotWidth,
  ) {
    final slot = _slotIndex(indexOnPage);
    final id = indexOnPage < pageIds.length ? pageIds[indexOnPage] : '';
    final selected = _selectedSlot == slot;

    return DragTarget<_DragItem>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final item = details.data;
        if (item.slotIndex != null) {
          unawaited(_swapSlots(item.slotIndex!, slot));
        } else {
          unawaited(_placeInSlot(slot, item.id));
        }
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        if (id.isEmpty) {
          return ToolbarEmptySlot(
            height: _layout.buttonHeight,
            colorScheme: scheme,
            selected: selected,
            highlighted: hovering,
            onTap: () => _tapSlot(slot),
          );
        }
        final button = ToolbarKeyButton(
          label: _labelForId(id),
          semanticLabel: _labelForId(id),
          height: _layout.buttonHeight,
          colorScheme: scheme,
          active: selected || hovering,
          onTap: () => _tapSlot(slot),
        );
        return LongPressDraggable<_DragItem>(
          data: _DragItem(id, slot),
          feedback: Material(
            color: scheme.uiSurface.invisible,
            child: SizedBox(width: slotWidth, child: button),
          ),
          childWhenDragging: ToolbarEmptySlot(
            height: _layout.buttonHeight,
            colorScheme: scheme,
          ),
          child: button,
        );
      },
    );
  }

  /// Page picker on the left, the grid's shape on the right.
  Widget _buildPageBar(Translations t) {
    return Row(
      children: [
        if (_layout.pages > 1)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int page = 0; page < _layout.pages; page++)
                    Padding(
                      padding: const EdgeInsets.only(right: AppTheme.space6),
                      child: _PageChip(
                        label: t.settings.layoutLabel(number: page + 1),
                        selected: _page == page,
                        onSelected: () => setState(() => _page = page),
                      ),
                    ),
                ],
              ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: AppTheme.space8),
        IconButton(
          tooltip: t.settings.toolbarGridSize,
          iconSize: AppTheme.icon20,
          icon: const Icon(PhosphorIconsRegular.gridFour),
          onPressed: _showGridSheet,
        ),
      ],
    );
  }

  /// The sheet's steppers are driven off this screen's own layout rather
  /// than the live setting: the profile being edited is not necessarily the
  /// one the toolbar draws, so they have to read what is on screen above
  /// them.
  Future<void> _showGridSheet() async {
    final t = Translations.of(context);
    await showAppSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ValueListenableBuilder<ToolbarLayout>(
          valueListenable: _layoutNotifier,
          builder: (ctx, layout, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.settings.toolbarGridSize,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.space8),
                StepperRow(
                  label: t.settings.toolbarColumns,
                  value: layout.columns,
                  min: kToolbarMinColumns,
                  max: kToolbarMaxColumns,
                  onChanged: (value) => _resize(columns: value),
                ),
                StepperRow(
                  label: t.settings.toolbarRows,
                  value: layout.rows,
                  min: kToolbarMinRows,
                  max: kToolbarMaxRows,
                  onChanged: (value) => _resize(rows: value),
                ),
                StepperRow(
                  label: t.settings.toolbarPages,
                  value: layout.pages,
                  min: kToolbarMinPages,
                  max: kToolbarMaxPages,
                  onChanged: (value) => _resize(pages: value),
                ),
                ValueStepperRow(
                  label: t.settings.toolbarButtonHeight,
                  value: layout.buttonHeight,
                  min: kToolbarMinButtonHeight,
                  max: kToolbarMaxButtonHeight,
                  step: 2,
                  display: layout.buttonHeight.toStringAsFixed(0),
                  onChanged: (value) =>
                      _applyLayout(layout.copyWith(buttonHeight: value)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One strip under the grid that says what is selected and what can be done
  /// with it.
  ///
  /// Always on screen, so it reads as part of the grid rather than something
  /// that appears and shoves the pool down. With nothing selected it carries
  /// the standing instruction, which is the only thing telling a first-timer
  /// how a key gets placed at all.
  Widget _buildSelectionBar(Translations t) {
    final slot = _selectedSlot;
    final id = slot == null ? '' : _idAt(slot);
    final action = id.isEmpty ? null : toolbarActionForId(id);
    final isCustom =
        action != null &&
        action.category == ToolbarActionCategory.custom &&
        action.id.startsWith(kToolbarCustomPrefix);
    final label = switch ((slot, id.isEmpty)) {
      (null, _) => t.settings.toolbarTapToPlace,
      (_, true) => t.settings.toolbarSlotSelected,
      _ => _labelForId(id),
    };

    return Container(
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space14,
        0,
        AppTheme.space6,
        0,
      ),
      decoration: BoxDecoration(
        color: slot == null
            ? context.colors.backgroundPrimary
            : context.colors.surfaceCard,
        border: Border(bottom: BorderSide(color: context.colors.surfaceBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: id.isEmpty
                      ? context.colors.uiSmall.copyWith(
                          color: slot == null
                              ? context.colors.textTertiary
                              : context.colors.primary,
                        )
                      : context.colors.itemTitle,
                ),
                if (id.isNotEmpty)
                  Text(
                    t.settings.toolbarKeyHeld,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.colors.uiSmall.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          if (isCustom)
            TextButton.icon(
              onPressed: () => _editCustomKey(action),
              icon: const Icon(
                PhosphorIconsRegular.pencilSimple,
                size: AppTheme.icon16,
              ),
              label: Text(t.common.edit),
            ),
          if (id.isNotEmpty)
            TextButton.icon(
              onPressed: () => _clearSlot(slot!),
              icon: const Icon(
                PhosphorIconsRegular.trash,
                size: AppTheme.icon16,
              ),
              label: Text(t.settings.toolbarSlotRemove),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
            ),
          if (slot != null)
            IconButton(
              tooltip: t.common.clearSelection,
              iconSize: AppTheme.icon18,
              onPressed: () => setState(() => _selectedSlot = null),
              icon: const Icon(PhosphorIconsRegular.x),
            ),
        ],
      ),
    );
  }

  List<(String, List<String>)> _poolSections() {
    final t = Translations.of(context);
    final query = _poolQuery.trim().toLowerCase();
    bool matches(String text) =>
        query.isEmpty || text.toLowerCase().contains(query);

    final sections = <(String, List<String>)>[];

    final customIds = [
      for (final id in toolbarSettings.customKeys.value)
        if (matches(toolbarActionForId(id)?.label ?? '')) id,
    ];
    if (customIds.isNotEmpty) {
      sections.add((t.toolbar.categoryCustom, customIds));
    }

    final snippetIds = [
      for (final snippet in ref.watch(snippetsProvider))
        if (matches(snippet.name)) toolbarSnippetActionId(snippet.id),
    ];
    if (snippetIds.isNotEmpty) sections.add((t.snippets.title, snippetIds));

    final grouped = <ToolbarActionCategory, List<String>>{};
    for (final id in kAllBuiltinIds) {
      final action = kToolbarActions[id]!;
      if (!matches(action.label) && !matches(action.id)) continue;
      grouped.putIfAbsent(action.category, () => []).add(id);
    }
    for (final entry in grouped.entries) {
      sections.add((toolbarCategoryLabel(t, entry.key), entry.value));
    }
    return sections;
  }

  /// A key in the pool, drawn at the width it would occupy in the grid.
  ///
  /// The pool used to size its keys at a fixed 62pt while the grid stretched
  /// its own, so the same key was two different shapes depending on which half
  /// of the screen it was in - and the point of sharing [ToolbarKeyButton] is
  /// that what is previewed is what gets drawn.
  Widget _buildPoolChip(String id, TerminalColorScheme scheme, double width) {
    final placed = _usedIds.contains(id);
    final button = SizedBox(
      width: width,
      child: Opacity(
        opacity: placed ? 0.45 : 1,
        child: ToolbarKeyButton(
          label: _labelForId(id),
          semanticLabel: _labelForId(id),
          height: _layout.buttonHeight,
          colorScheme: scheme,
          onTap: () => _poolKeyTapped(id),
        ),
      ),
    );
    if (placed) return button;
    return LongPressDraggable<_DragItem>(
      data: _DragItem(id),
      feedback: Material(
        color: scheme.uiSurface.invisible,
        child: SizedBox(width: width, child: button),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: button),
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final scheme = toolbarSchemeFromTheme(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.settings.toolbarLayout)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final sections = _poolSections();

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          AppActionDropdown<_ScreenAction>(
            width: 220,
            items: [
              DropdownItem(
                value: _ScreenAction.grid,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsRegular.gridFour,
                  label: t.settings.toolbarGridSize,
                ),
              ),
              DropdownItem(
                value: _ScreenAction.reset,
                intrinsicHeight: true,
                child: AppDropdownItem(
                  icon: PhosphorIconsRegular.arrowCounterClockwise,
                  label: t.settings.toolbarReset,
                  color: context.colors.error,
                ),
              ),
            ],
            onSelected: (action) => switch (action) {
              _ScreenAction.grid => unawaited(_showGridSheet()),
              _ScreenAction.reset => unawaited(_reset()),
            },
          ),
          const SizedBox(width: AppTheme.space4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth - AppTheme.space12 * 2;
            final slotWidth =
                (available - _kSlotGap * (_layout.columns - 1)) /
                _layout.columns;
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space12,
                    AppTheme.space8,
                    AppTheme.space12,
                    AppTheme.space12,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.backgroundPrimary,
                    border: Border(
                      bottom: BorderSide(color: context.colors.surfaceBorder),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPageBar(t),
                      const SizedBox(height: AppTheme.space10),
                      _buildGrid(scheme, slotWidth),
                    ],
                  ),
                ),
                _buildSelectionBar(t),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space12,
                    AppTheme.space10,
                    AppTheme.space12,
                    AppTheme.space6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppSearchField(
                          controller: _searchController,
                          hint: t.toolbar.searchHint,
                          clearTooltip: t.common.clearSearch,
                          dense: true,
                          onChanged: (value) =>
                              setState(() => _poolQuery = value),
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      IconButton.filledTonal(
                        tooltip: t.settings.toolbarAddCustom,
                        icon: const Icon(
                          PhosphorIconsRegular.plus,
                          size: AppTheme.icon18,
                        ),
                        onPressed: _addCustomKey,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: sections.isEmpty
                      ? Center(
                          child: Text(
                            t.toolbar.noResults,
                            style: TextStyle(
                              color: context.colors.textTertiary,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.space12,
                            0,
                            AppTheme.space12,
                            AppTheme.space32,
                          ),
                          children: [
                            for (final (title, ids) in sections) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppTheme.space12,
                                  bottom: AppTheme.space6,
                                ),
                                child: SectionHeader(title),
                              ),
                              Wrap(
                                spacing: _kSlotGap,
                                runSpacing: _kSlotGap,
                                children: [
                                  for (final id in ids)
                                    _buildPoolChip(id, scheme, slotWidth),
                                ],
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DragItem {
  final String id;
  final int? slotIndex;
  const _DragItem(this.id, [this.slotIndex]);
}

/// A page tab that also turns the page when a key is dragged onto it.
///
/// Without this a drag can only ever reach slots already on screen, which
/// leaves dropping a key on another page with no gesture at all - the tap-then
/// -tap move is the other half of the answer.
///
/// Never the drop target itself: the page turns and the drag carries on to a
/// slot on it. It also hides the selection checkmark Material would add,
/// since that would widen the chip and shunt every page after it sideways
/// as you switch - the page being on is worth saying in colour, not width.
class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragItem>(
      onWillAcceptWithDetails: (_) {
        if (!selected) onSelected();
        return false;
      },
      builder: (context, candidate, _) =>
          TagChip(label: label, selected: selected, onTap: onSelected),
    );
  }
}

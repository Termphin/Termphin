import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/action_dock_settings.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../../widgets/ui/action_dock_tile.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// What the action dock lists, drawn as the panel itself, tile for tile, over
/// a tray of the hidden ones.
///
/// Dragging a tile inserts it where it is let go - a bar on the tile under it
/// shows which side - rather than swapping the two, and a tile from the tray
/// can be dragged straight to its place. Hiding and showing go through the
/// badge in each tile's corner, so a stray tap on the panel changes nothing.
///
/// The switch that shows the dock at all is in Settings, next to the key
/// toolbar's own: this screen is only reachable while the dock is on, so a
/// switch here would be a way to turn off the feature you are standing
/// inside.
class ActionDockSettingsScreen extends StatefulWidget {
  const ActionDockSettingsScreen({super.key});

  @override
  State<ActionDockSettingsScreen> createState() =>
      _ActionDockSettingsScreenState();
}

class _ActionDockSettingsScreenState extends State<ActionDockSettingsScreen> {
  DockLayout _layout = kDefaultDockLayout;
  bool _loading = true;

  /// The tile being dragged, which decides the side of the insertion bar and
  /// whether the slot past the last tile is drawn.
  DockAction? _dragging;

  @override
  void initState() {
    super.initState();
    unawaited(
      AnalyticsService.instance.screen(AnalyticsScreen.actionDockSettings),
    );
    _load();
  }

  Future<void> _load() async {
    await actionDockSettings.load();
    if (!mounted) return;
    setState(() {
      _layout = (
        order: actionDockSettings.order.value,
        hidden: actionDockSettings.hidden.value,
      );
      _loading = false;
    });
  }

  List<DockAction> get _visible => [
    for (final a in _layout.order)
      if (!_layout.hidden.contains(a)) a,
  ];

  List<DockAction> get _hiddenInOrder => [
    for (final a in _layout.order)
      if (_layout.hidden.contains(a)) a,
  ];

  /// The last write still in flight. Each one waits for the one before it, so
  /// two quick edits reach storage in the order they were made.
  Future<void> _pendingWrite = Future.value();

  /// Stores [next] and shows it, if the screen is still there - an undo from
  /// the toast can arrive after the user has left.
  Future<void> _apply(DockLayout next) {
    if (mounted) setState(() => _layout = next);
    return _pendingWrite = _pendingWrite.then(
      (_) => Future.wait([
        actionDockSettings.order.set(next.order),
        actionDockSettings.hidden.set(next.hidden),
      ]),
    );
  }

  void _place(DockAction action, int index) =>
      unawaited(_apply(placeDockAction(_layout, action, index)));

  void _hide(DockAction action) =>
      unawaited(_apply(hideDockAction(_layout, action)));

  void _show(DockAction action) => _place(action, _visible.length);

  /// True when [dragged] lands after the tile at [index] rather than before
  /// it - which happens only when it is moving forward along the panel.
  bool _landsAfter(DockAction dragged, int index) {
    final from = _visible.indexOf(dragged);
    return from >= 0 && from < index;
  }

  Future<void> _reset() async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.actionDockResetTitle,
      message: t.settings.actionDockResetMessage,
      confirmLabel: t.common.reset,
    );
    if (!confirmed || !mounted) return;
    final previous = _layout;
    await _apply(kDefaultDockLayout);
    if (!mounted) return;
    AppNotifications.success(
      context,
      t.settings.actionDockResetDone,
      actionLabel: t.common.undo,
      onAction: () => unawaited(_apply(previous)),
    );
  }

  void _setDragging(DockAction? action) => setState(() => _dragging = action);

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return LargeTitleScaffold(
      title: t.settings.actionDock,
      actions: [
        IconButton(
          tooltip: t.settings.actionDockReset,
          onPressed: _loading ? null : () => unawaited(_reset()),
          icon: const Icon(PhosphorIconsRegular.arrowCounterClockwise),
        ),
      ],
      bodyBuilder: (context, scrollController, gutter) => _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32).add(gutter),
              children: [
                LargeTitleHeader(
                  title: t.settings.actionDock,
                  subtitle: t.settings.actionDockSubtitle,
                  padding: const EdgeInsets.only(top: 24, bottom: 8),
                ),
                const SizedBox(height: 16),
                Column(
                  key: const ValueKey('actionDockEditor'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(t.settings.actionDockPreview),
                    const SizedBox(height: 8),
                    Center(child: _buildPanel(t)),
                    const SizedBox(height: 24),
                    _SectionLabel(t.settings.actionDockHiddenLabel),
                    const SizedBox(height: 8),
                    Center(child: _buildTray(t)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildPanel(Translations t) {
    final visible = _visible;
    final dragging = _dragging;
    return SizedBox(
      width: kPalettePanelWidth,
      child: ActionDockPanel(
        child: visible.isEmpty && dragging == null
            ? _EmptyNote(t.settings.actionDockAllHidden)
            : Wrap(
                spacing: kPaletteTileSpacing,
                runSpacing: kPaletteTileSpacing,
                children: [
                  for (final (index, action) in visible.indexed)
                    _PanelTile(
                      key: ValueKey(action),
                      action: action,
                      label: dockActionLabel(t, action),
                      hideLabel: t.settings.actionDockHide(
                        name: dockActionLabel(t, action).replaceAll('\n', ' '),
                      ),
                      landsAfter: (dragged) => _landsAfter(dragged, index),
                      onAccept: (dragged) => _place(dragged, index),
                      onHide: () => _hide(action),
                      onDragStarted: () => _setDragging(action),
                      onDragEnd: () => _setDragging(null),
                    ),
                  if (dragging != null &&
                      (_layout.hidden.contains(dragging) ||
                          visible.last != dragging))
                    _EndSlot(onAccept: _show),
                ],
              ),
      ),
    );
  }

  /// Everything switched off, in the same tiles - so a hidden action reads as
  /// the same thing it will be once it's back on the panel.
  Widget _buildTray(Translations t) {
    final hidden = _hiddenInOrder;
    return SizedBox(
      width: kPalettePanelWidth,
      child: DragTarget<DockAction>(
        onWillAcceptWithDetails: (d) => !_layout.hidden.contains(d.data),
        onAcceptWithDetails: (d) => _hide(d.data),
        builder: (context, candidates, _) => AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? context.colors.primary.withValues(alpha: 0.07)
                : context.colors.primary.invisible,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: candidates.isNotEmpty
                  ? context.colors.primary.withValues(alpha: 0.5)
                  : context.colors.surfaceBorder.withValues(alpha: 0.6),
            ),
          ),
          padding: const EdgeInsets.all(kPalettePanelPadding),
          child: hidden.isEmpty
              ? _EmptyNote(t.settings.actionDockNoneHidden)
              : Wrap(
                  spacing: kPaletteTileSpacing,
                  runSpacing: kPaletteTileSpacing,
                  children: [
                    for (final action in hidden)
                      _TrayTile(
                        key: ValueKey(action),
                        action: action,
                        label: dockActionLabel(t, action),
                        showLabel: t.settings.actionDockShow(
                          name: dockActionLabel(
                            t,
                            action,
                          ).replaceAll('\n', ' '),
                        ),
                        onShow: () => _show(action),
                        onDragStarted: () => _setDragging(action),
                        onDragEnd: () => _setDragging(null),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A plain drag under a mouse, where a press-and-move is unambiguous; a
/// long-press drag under a finger, where the same move scrolls the page.
class _EditorDraggable extends StatelessWidget {
  const _EditorDraggable({
    required this.action,
    required this.feedback,
    required this.childWhenDragging,
    required this.child,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  final DockAction action;
  final Widget feedback;
  final Widget childWhenDragging;
  final Widget child;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final wrappedFeedback = Material(
      color: context.colors.primary.invisible,
      child: feedback,
    );
    if (isDesktopPlatform) {
      return Draggable<DockAction>(
        data: action,
        feedback: wrappedFeedback,
        childWhenDragging: childWhenDragging,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnd(),
        child: child,
      );
    }
    return LongPressDraggable<DockAction>(
      data: action,
      feedback: wrappedFeedback,
      childWhenDragging: childWhenDragging,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd(),
      child: child,
    );
  }
}

/// A tile on the panel: draggable to a new place, a drop target that inserts
/// whatever is let go on it, and a badge that hides it.
class _PanelTile extends StatelessWidget {
  const _PanelTile({
    super.key,
    required this.action,
    required this.label,
    required this.hideLabel,
    required this.landsAfter,
    required this.onAccept,
    required this.onHide,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  final DockAction action;
  final String label;
  final String hideLabel;
  final bool Function(DockAction dragged) landsAfter;
  final ValueChanged<DockAction> onAccept;
  final VoidCallback onHide;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final icon = dockActionIcon(action);
    return DragTarget<DockAction>(
      onWillAcceptWithDetails: (d) => d.data != action,
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidates, _) {
        final dragged = candidates.whereType<DockAction>().firstOrNull;
        return _EditorDraggable(
          action: action,
          feedback: ActionDockTile(icon: icon, label: label, highlighted: true),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: ActionDockTile(icon: icon, label: label),
          ),
          onDragStarted: onDragStarted,
          onDragEnd: onDragEnd,
          child: Stack(
            children: [
              ActionDockTile(
                icon: icon,
                label: label,
                highlighted: dragged != null,
              ),
              if (dragged != null) _InsertBar(after: landsAfter(dragged)),
              Positioned(
                top: 0,
                right: 0,
                child: _Badge(
                  icon: PhosphorIconsRegular.minus,
                  color: context.colors.textTertiary,
                  semanticLabel: hideLabel,
                  onTap: onHide,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A hidden tile: tap anywhere or its badge to put it back at the end of the
/// panel, or drag it to the place it should take.
class _TrayTile extends StatelessWidget {
  const _TrayTile({
    super.key,
    required this.action,
    required this.label,
    required this.showLabel,
    required this.onShow,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  final DockAction action;
  final String label;
  final String showLabel;
  final VoidCallback onShow;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final icon = dockActionIcon(action);
    return _EditorDraggable(
      action: action,
      feedback: ActionDockTile(icon: icon, label: label, highlighted: true),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: ActionDockTile(icon: icon, label: label, dimmed: true),
      ),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      child: Stack(
        children: [
          ActionDockTile(icon: icon, label: label, dimmed: true, onTap: onShow),
          Positioned(
            top: 0,
            right: 0,
            child: _Badge(
              icon: PhosphorIconsRegular.plus,
              color: context.colors.primary,
              semanticLabel: showLabel,
              onTap: onShow,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a tile dragged past the last one lands: an outlined empty slot,
/// drawn only during a drag that could end there.
class _EndSlot extends StatelessWidget {
  const _EndSlot({required this.onAccept});

  final ValueChanged<DockAction> onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<DockAction>(
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidates, _) => AnimatedContainer(
        key: const ValueKey('actionDockEndSlot'),
        duration: AppTheme.interactiveDuration,
        width: kPaletteTileWidth,
        height: kPaletteTileHeight,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? context.colors.primary.withValues(alpha: 0.12)
              : context.colors.primary.invisible,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: context.colors.primary.withValues(
              alpha: candidates.isNotEmpty ? 0.6 : 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// The edge of a tile a drop would land against.
class _InsertBar extends StatelessWidget {
  const _InsertBar({required this.after});

  final bool after;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      bottom: 10,
      left: after ? null : 0,
      right: after ? 0 : null,
      child: Container(
        width: 3,
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The small round button in a tile's corner. Its hit area is larger than
/// the dot so it is easy to hit with a thumb, and stays inside the tile so
/// the tile's own hit test reaches it. The tooltip shows on hover only: a
/// long press on a tile belongs to the drag.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: semanticLabel,
      triggerMode: TooltipTriggerMode.manual,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                margin: const EdgeInsets.all(4),
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 11, color: context.colors.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kPaletteTileHeight,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
        ),
      ),
    );
  }
}

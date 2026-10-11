import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/settings/action_dock_settings.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/action_dock_tile.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// What the action dock lists, drawn as the panel itself, tile for tile.
/// Drag one tile onto another to reorder, tap it to move it in or out of the
/// tray below.
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
  List<DockAction> _order = DockAction.values;
  Set<DockAction> _hidden = kDefaultHiddenDockActions;
  bool _loading = true;

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
      _order = actionDockSettings.order.value;
      _hidden = actionDockSettings.hidden.value;
      _loading = false;
    });
  }

  List<DockAction> get _visible => [
    for (final a in _order)
      if (!_hidden.contains(a)) a,
  ];

  List<DockAction> get _hiddenInOrder => [
    for (final a in _order)
      if (_hidden.contains(a)) a,
  ];

  /// Swaps two actions inside the full order, so the hidden ones sitting
  /// between them keep their own places.
  Future<void> _swap(DockAction a, DockAction b) async {
    if (a == b) return;
    final next = List<DockAction>.from(_order);
    final ia = next.indexOf(a);
    final ib = next.indexOf(b);
    if (ia < 0 || ib < 0) return;
    next[ia] = b;
    next[ib] = a;
    setState(() => _order = next);
    await actionDockSettings.order.set(next);
  }

  Future<void> _setHidden(DockAction action, bool hidden) async {
    final next = Set<DockAction>.from(_hidden);
    if (hidden) {
      next.add(action);
    } else {
      next.remove(action);
    }
    setState(() => _hidden = next);
    await actionDockSettings.hidden.set(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return LargeTitleScaffold(
      title: t.settings.actionDock,
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
    return SizedBox(
      width: kPalettePanelWidth,
      child: ActionDockPanel(
        child: visible.isEmpty
            ? _EmptyNote(t.settings.actionDockAllHidden)
            : Wrap(
                spacing: kPaletteTileSpacing,
                runSpacing: kPaletteTileSpacing,
                children: [
                  for (final action in visible)
                    _DraggableTile(
                      action: action,
                      label: dockActionLabel(t, action),
                      onAcceptAction: (dragged) => _swap(dragged, action),
                      onTap: () => unawaited(_setHidden(action, true)),
                    ),
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
        onWillAcceptWithDetails: (d) => !_hidden.contains(d.data),
        onAcceptWithDetails: (d) => unawaited(_setHidden(d.data, true)),
        builder: (context, candidates, _) => AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? context.colors.primary.withValues(alpha: 0.07)
                : context.colors.primary.invisible,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: context.colors.surfaceBorder.withValues(alpha: 0.6),
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
                      ActionDockTile(
                        icon: dockActionIcon(action),
                        label: dockActionLabel(t, action),
                        dimmed: true,
                        onTap: () => unawaited(_setHidden(action, false)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A tile on the panel: draggable onto another to swap the two, and itself a
/// drop target for whichever one is being dragged.
class _DraggableTile extends StatelessWidget {
  const _DraggableTile({
    required this.action,
    required this.label,
    required this.onAcceptAction,
    required this.onTap,
  });

  final DockAction action;
  final String label;
  final ValueChanged<DockAction> onAcceptAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = dockActionIcon(action);
    return DragTarget<DockAction>(
      onWillAcceptWithDetails: (d) => d.data != action,
      onAcceptWithDetails: (d) => onAcceptAction(d.data),
      builder: (context, candidates, _) => LongPressDraggable<DockAction>(
        data: action,
        feedback: Material(
          color: context.colors.primary.invisible,
          child: ActionDockTile(icon: icon, label: label, highlighted: true),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: ActionDockTile(icon: icon, label: label),
        ),
        child: ActionDockTile(
          icon: icon,
          label: label,
          highlighted: candidates.isNotEmpty,
          onTap: onTap,
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/terminal_settings.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../ui/app_sheet.dart';
import '../ui/segmented_switch.dart';
import '../ui/settings_controls.dart';
import '../ui/stepper_row.dart';
import '../ui/toolbar_key_button.dart';
import 'special_keys_toolbar.dart'
    show toolbarActionSemanticLabel, toolbarSchemeFromTheme;
import 'terminal_scheme_theme.dart';

enum SessionQuickTab { toolbar, appearance }

/// Where the sheet sends the user once it has closed.
enum _Exit { manageToolbars, openAppearance }

/// What a session lets the user change without leaving it: which toolbar
/// layout is drawn, and how the terminal looks.
///
/// [onManageToolbars] and [onOpenAppearance] run after the sheet has closed,
/// so the screen they push lands on the caller's navigator rather than inside
/// a route on its way out. Without [showToolbarTab] - the toolbar switched off
/// - there is nothing to switch, and the sheet is the appearance tab alone.
///
/// A scheme picked here repaints the sheet's own surface too, not only the
/// session behind it.
Future<void> showSessionQuickSheet(
  BuildContext context, {
  required VoidCallback onManageToolbars,
  required VoidCallback onOpenAppearance,
  bool showToolbarTab = true,
  Map<String, String> snippetLabels = const {},
}) async {
  _Exit? exit;
  await showAppSheet<void>(
    context: context,
    surface: (sheet) => TerminalSchemeTheme(child: _LiveSurface(child: sheet)),
    builder: (sheetCtx) => SessionQuickSheet(
      showToolbarTab: showToolbarTab,
      snippetLabels: snippetLabels,
      onPicked: () => Navigator.of(sheetCtx).pop(),
      onManageToolbars: () {
        exit = _Exit.manageToolbars;
        Navigator.of(sheetCtx).pop();
      },
      onOpenAppearance: () {
        exit = _Exit.openAppearance;
        Navigator.of(sheetCtx).pop();
      },
    ),
  );
  switch (exit) {
    case _Exit.manageToolbars:
      onManageToolbars();
    case _Exit.openAppearance:
      onOpenAppearance();
    case null:
      break;
  }
}

/// The sheet's background, drawn from the theme it sits in rather than the
/// one its route was opened under.
class _LiveSurface extends StatelessWidget {
  const _LiveSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape =
        Theme.of(context).bottomSheetTheme.shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXl),
          ),
        );
    return DecoratedBox(
      key: const ValueKey('sessionQuickSurface'),
      decoration: ShapeDecoration(
        color: context.colors.surfaceCard,
        shape: shape,
      ),
      child: child,
    );
  }
}

class SessionQuickSheet extends StatefulWidget {
  const SessionQuickSheet({
    super.key,
    required this.onPicked,
    required this.onManageToolbars,
    required this.onOpenAppearance,
    this.showToolbarTab = true,
    this.snippetLabels = const {},
  });

  /// A layout was chosen - the sheet's job is done.
  final VoidCallback onPicked;
  final VoidCallback onManageToolbars;
  final VoidCallback onOpenAppearance;
  final bool showToolbarTab;
  final Map<String, String> snippetLabels;

  @override
  State<SessionQuickSheet> createState() => _SessionQuickSheetState();
}

class _SessionQuickSheetState extends State<SessionQuickSheet> {
  late SessionQuickTab _tab = widget.showToolbarTab
      ? SessionQuickTab.toolbar
      : SessionQuickTab.appearance;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Text(
            widget.showToolbarTab
                ? t.toolbar.quickSettings
                : t.toolbar.quickTabAppearance,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (widget.showToolbarTab)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SegmentedSwitch<SessionQuickTab>(
              selected: _tab,
              segments: [
                SwitchSegment(
                  key: const ValueKey('sessionQuickTab-toolbar'),
                  value: SessionQuickTab.toolbar,
                  icon: PhosphorIconsFill.keyboard,
                  label: t.toolbar.quickTabToolbar,
                ),
                SwitchSegment(
                  key: const ValueKey('sessionQuickTab-appearance'),
                  value: SessionQuickTab.appearance,
                  icon: PhosphorIconsFill.palette,
                  label: t.toolbar.quickTabAppearance,
                ),
              ],
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          ),
        Flexible(
          child: switch (_tab) {
            SessionQuickTab.toolbar => _ToolbarTab(
              snippetLabels: widget.snippetLabels,
              onPicked: widget.onPicked,
              onManage: widget.onManageToolbars,
            ),
            SessionQuickTab.appearance => _AppearanceTab(
              onOpenAll: widget.onOpenAppearance,
            ),
          },
        ),
      ],
    );
  }
}

/// The card everything in the sheet sits on - the add-session sheet's, so the
/// two read as one family.
class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.child, this.onTap, this.highlighted = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    final decoration = BoxDecoration(
      color: context.colors.surfaceElevated,
      borderRadius: radius,
      border: Border.all(
        color: highlighted
            ? context.colors.primary
            : context.colors.surfaceBorder,
        width: highlighted ? 1.5 : 1,
      ),
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: context.colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: Ink(
        decoration: decoration,
        child: InkWell(onTap: onTap, borderRadius: radius, child: child),
      ),
    );
  }
}

/// An accent icon and label leading off the sheet, the way "New session"
/// does under a machine.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SheetCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            Icon(icon, size: 16, color: context.colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: context.colors.uiStyle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.primary,
                ),
              ),
            ),
            Icon(
              PhosphorIconsRegular.caretRight,
              size: 14,
              color: context.colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Every saved layout, each drawn as it would look over the terminal. A tap
/// hands the toolbar to that layout.
class _ToolbarTab extends StatelessWidget {
  const _ToolbarTab({
    required this.snippetLabels,
    required this.onPicked,
    required this.onManage,
  });

  final Map<String, String> snippetLabels;
  final VoidCallback onPicked;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return ValueListenableBuilder<ToolbarProfiles>(
      valueListenable: toolbarSettings.profiles,
      builder: (context, profiles, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          for (final profile in profiles.profiles) ...[
            _ProfileCard(
              profile: profile,
              active: profile.id == profiles.activeId,
              snippetLabels: snippetLabels,
              onTap: () async {
                unawaited(HapticFeedback.selectionClick());
                if (profile.id != profiles.activeId) {
                  await activateToolbarProfile(profile.id);
                }
                onPicked();
              },
            ),
            const SizedBox(height: 12),
          ],
          _ActionRow(
            key: const ValueKey('sessionQuickManageToolbars'),
            icon: PhosphorIconsRegular.gridFour,
            label: t.toolbar.manageLayouts,
            onTap: onManage,
          ),
        ],
      ),
    );
  }
}

/// A layout as a card: its name, a mark when it is the one in use, and the
/// keys of its first page on a strip in the toolbar's own colours. The keys
/// say what the layout is; counting them would only repeat it.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.snippetLabels,
    required this.onTap,
  });

  final ToolbarProfile profile;
  final bool active;
  final Map<String, String> snippetLabels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final name = profile.name.isEmpty
        ? t.settings.toolbarProfileDefault
        : profile.name;
    return Semantics(
      selected: active,
      child: KeyedSubtree(
        key: ValueKey('toolbarProfileCard-${profile.id}'),
        child: _SheetCard(
          onTap: onTap,
          highlighted: active,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.uiStyle.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? context.colors.textPrimary
                              : context.colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      active
                          ? PhosphorIconsFill.radioButton
                          : PhosphorIconsRegular.circle,
                      size: 20,
                      color: active
                          ? context.colors.primary
                          : context.colors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ToolbarLayoutPreview(
                  layout: profile.layout,
                  snippetLabels: snippetLabels,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page of [layout] as the toolbar draws it, keys and all, but inert: a
/// tap anywhere on it belongs to the card around it.
///
/// Keys are capped in height so a list of tall layouts still fits on screen;
/// their width, order and labels are the real ones.
class ToolbarLayoutPreview extends StatelessWidget {
  const ToolbarLayoutPreview({
    super.key,
    required this.layout,
    this.snippetLabels = const {},
    this.page,
  });

  static const _kRowGap = 3.0;
  static const _kMaxKeyHeight = 30.0;
  static const _kPadding = 4.0;

  /// How tall a page of [layout] is drawn when every row has a key - for a
  /// pager that has to fix its height before it knows which page is shown.
  static double heightFor(ToolbarLayout layout) {
    final key = math.min(layout.buttonHeight, _kMaxKeyHeight);
    return layout.rows * key + (layout.rows - 1) * _kRowGap + _kPadding * 2;
  }

  final ToolbarLayout layout;
  final Map<String, String> snippetLabels;

  /// Which page to draw; the first one with keys on it when null.
  final int? page;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final scheme = toolbarSchemeFromTheme(context);
    final keyHeight = math.min(layout.buttonHeight, _kMaxKeyHeight);
    final ids = layout.pageIds(page ?? layout.visiblePages.first);
    final rows = <Widget>[];
    for (int row = 0; row < layout.rows; row++) {
      final rowIds = ids
          .skip(row * layout.columns)
          .take(layout.columns)
          .toList();
      if (rowIds.every((id) => id.isEmpty)) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _kRowGap));
      rows.add(
        Row(
          children: [
            for (final id in rowIds)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _key(t, scheme, id, keyHeight),
                ),
              ),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        SizedBox(
          height: keyHeight,
          child: Center(
            child: Text(
              t.toolbar.emptyLayout,
              style: context.colors.uiSmall.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(_kPadding),
          decoration: BoxDecoration(
            color: context.colors.backgroundPrimary,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }

  Widget _key(
    Translations t,
    TerminalColorScheme scheme,
    String id,
    double height,
  ) {
    final action = toolbarActionForId(id);
    if (action == null) return SizedBox(height: height);
    final label = action.kind == ToolbarActionKind.snippet
        ? snippetLabels[action.payload] ?? action.label
        : action.label;
    return ToolbarKeyButton(
      label: shortToolbarLabel(label),
      semanticLabel: toolbarActionSemanticLabel(t, action),
      onTap: () {},
      height: height,
      colorScheme: scheme,
    );
  }
}

/// The handful of terminal settings worth changing mid-session, drawn with
/// the same controls as the terminal appearance screen. Every change writes
/// through at once, so the session behind the sheet follows it.
class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab({required this.onOpenAll});

  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final settings = terminalSettings;
    return ListenableBuilder(
      listenable: settings.changes,
      builder: (context, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _SheetCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsDropdownField(
                    key: const ValueKey('quickSchemeField'),
                    label: t.settings.colorScheme,
                    value: settings.scheme.value,
                    labels: kTerminalSchemeLabels,
                    onChanged: (v) => unawaited(settings.scheme.set(v)),
                  ),
                  const SizedBox(height: 16),
                  SettingsDropdownField(
                    key: const ValueKey('quickFontField'),
                    label: t.settings.font,
                    value: settings.fontFamily.value,
                    labels: kTerminalFontLabels,
                    itemsInOwnFont: true,
                    onChanged: (v) => unawaited(settings.fontFamily.set(v)),
                  ),
                  const SizedBox(height: 16),
                  ValueStepperRow(
                    label: t.settings.fontSize,
                    value: settings.fontSize.value,
                    display: settings.fontSize.value.toStringAsFixed(1),
                    min: 8,
                    max: 24,
                    step: 0.5,
                    onChanged: (v) => unawaited(settings.fontSize.set(v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            key: const ValueKey('sessionQuickOpenAppearance'),
            icon: PhosphorIconsRegular.slidersHorizontal,
            label: t.toolbar.allTerminalSettings,
            onTap: onOpenAll,
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../services/settings/toolbar_share_link.dart';
import '../../theme/theme.dart';
import '../ui/app_badge.dart';
import '../ui/app_divider.dart';
import '../ui/app_notifications.dart';
import '../ui/app_sheet.dart';
import 'session_quick_sheet.dart' show ToolbarLayoutPreview;

/// Asks before a toolbar from a link becomes one of the user's layouts.
///
/// A link is something somebody else hands you, and a text key types whatever
/// its author chose - one ending in Enter runs it on the server with a single
/// tap. So the sheet draws the layout as it will look, a page at a time as
/// the toolbar shows it, says how many keys type text and how many of those
/// press Enter, and lists every one of them word for word a tap away. The
/// layout is added beside the others; it only replaces the toolbar in use
/// when the user picks "Add and use".
Future<void> showToolbarImportSheet(BuildContext context, ToolbarShare share) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => ToolbarImportSheet(share: share),
  );
}

class ToolbarImportSheet extends StatefulWidget {
  const ToolbarImportSheet({super.key, required this.share});

  final ToolbarShare share;

  @override
  State<ToolbarImportSheet> createState() => _ToolbarImportSheetState();
}

/// Never the whole screen: past a height ceiling the keys scroll inside
/// the sheet, and the title and the buttons stay where they are.
class _ToolbarImportSheetState extends State<ToolbarImportSheet> {
  bool _busy = false;
  bool _showKeys = false;

  Future<void> _add({required bool use}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = Translations.of(context);
    final share = widget.share;
    final profile = ToolbarProfile(
      id: const Uuid().v4(),
      name: share.name.isEmpty ? t.toolbar.importUnnamed : share.name,
      layout: share.layout,
    );
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(profile, activate: false),
    );
    if (use) await activateToolbarProfile(profile.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    AppNotifications.success(context, t.toolbar.importAdded);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final share = widget.share;
    final textKeys = [
      for (final id in share.layout.order)
        if (toolbarActionForId(id) case final action?
            when action.kind == ToolbarActionKind.text)
          action,
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space14,
              AppTheme.space20,
              AppTheme.space2,
            ),
            child: Text(
              t.toolbar.importTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              0,
              AppTheme.space20,
              AppTheme.space12,
            ),
            child: Text(
              share.name.isEmpty ? t.toolbar.importUnnamed : share.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.colors.uiStyle.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PagedPreview(layout: share.layout),
                  if (textKeys.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space12),
                    _TextKeys(
                      keys: textKeys,
                      expanded: _showKeys,
                      onToggle: () => setState(() => _showKeys = !_showKeys),
                    ),
                  ],
                  if (share.droppedKeys > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.space4,
                        AppTheme.space10,
                        AppTheme.space4,
                        0,
                      ),
                      child: Text(
                        t.toolbar.importDropped(count: share.droppedKeys),
                        style: context.colors.uiSmall.copyWith(
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('toolbarImportAdd'),
                    onPressed: _busy ? null : () => unawaited(_add(use: false)),
                    child: Text(t.toolbar.importAdd),
                  ),
                ),
                const SizedBox(width: AppTheme.space10),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('toolbarImportAddAndUse'),
                    onPressed: _busy ? null : () => unawaited(_add(use: true)),
                    child: Text(t.toolbar.importAddAndUse),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The layout a page at a time, the way the toolbar shows it: swipe between
/// pages, with the toolbar's own indicator under them.
class _PagedPreview extends StatefulWidget {
  const _PagedPreview({required this.layout});

  final ToolbarLayout layout;

  @override
  State<_PagedPreview> createState() => _PagedPreviewState();
}

class _PagedPreviewState extends State<_PagedPreview> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final pages = layout.visiblePages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: ToolbarLayoutPreview.heightFor(layout),
          child: PageView(
            controller: _controller,
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              for (final page in pages)
                Align(
                  alignment: Alignment.topCenter,
                  child: ToolbarLayoutPreview(
                    key: ValueKey('importPreviewPage-$page'),
                    layout: layout,
                    page: page,
                  ),
                ),
            ],
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: AppTheme.space6),
          Row(
            children: [
              for (var i = 0; i < pages.length; i++) ...[
                if (i > 0) const SizedBox(width: AppTheme.space6),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _controller.animateToPage(
                        i,
                        duration: AppTheme.motionFast,
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.space4,
                      ),
                      child: AnimatedContainer(
                        duration: AppTheme.motionFast,
                        height: 2,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? context.colors.primary
                              : context.colors.surfaceBorder,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// How many keys type text and how many of those press Enter, opening into
/// each one word for word.
class _TextKeys extends StatelessWidget {
  const _TextKeys({
    required this.keys,
    required this.expanded,
    required this.onToggle,
  });

  final List<ToolbarAction> keys;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final entering = keys.where((key) => key.appendEnter).length;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: context.colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: context.colors.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('toolbarImportTextKeys'),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space14,
                AppTheme.space12,
                AppTheme.space12,
                AppTheme.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    entering > 0
                        ? PhosphorIconsRegular.warningCircle
                        : PhosphorIconsRegular.textT,
                    size: AppTheme.icon18,
                    color: entering > 0
                        ? context.colors.warning
                        : context.colors.textSecondary,
                  ),
                  const SizedBox(width: AppTheme.space10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entering > 0
                              ? '${t.toolbar.importTextKeys(n: keys.length)} · '
                                    '${t.toolbar.importPressEnter(n: entering)}'
                              : t.toolbar.importTextKeys(n: keys.length),
                          style: context.colors.uiStyle.copyWith(
                            fontSize: AppTheme.font13,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        if (entering > 0) ...[
                          const SizedBox(height: AppTheme.space2),
                          Text(
                            t.toolbar.importEnterNote,
                            style: context.colors.uiSmall.copyWith(
                              color: context.colors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppTheme.motionFast,
                    child: Icon(
                      PhosphorIconsRegular.caretDown,
                      size: AppTheme.icon16,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppTheme.motionFast,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final key in keys) ...[
                        const AppDivider(),
                        _TextKeyRow(action: key),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shows the key's own name when it says something the text does not - a
/// lone backslash reads as nothing until it says it is the new-line key.
class _TextKeyRow extends StatelessWidget {
  const _TextKeyRow({required this.action});

  final ToolbarAction action;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = action.payload ?? action.label;
    final named = action.label != text;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space14,
        vertical: AppTheme.space8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _visible(text),
              style: TextStyle(
                fontFamily: 'JetBrainsMonoNerdFontMono',
                fontSize: AppTheme.font12,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (named) ...[
            const SizedBox(width: AppTheme.space8),
            Text(
              action.label,
              style: context.colors.uiSmall.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ],
          if (action.appendEnter) ...[
            const SizedBox(width: AppTheme.space8),
            AppBadge(t.toolbar.importEnter, tone: BadgeTone.warning),
          ],
        ],
      ),
    );
  }
}

/// Control characters named, so a key that sends Esc or a line break says so
/// instead of showing nothing - or a glyph the font does not have.
String _visible(String text) => text
    .replaceAll('\u001b', '[Esc]')
    .replaceAll('\r', '[Enter]')
    .replaceAll('\n', '[Enter]')
    .replaceAll('\t', '[Tab]');

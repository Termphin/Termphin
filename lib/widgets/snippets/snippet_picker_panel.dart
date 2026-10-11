import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../models/snippet.dart';
import '../../providers/groups_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/platform_info.dart';
import '../terminal/terminal_scheme_theme.dart';
import '../ui/group_filter_chips.dart';
import 'snippet_args_dialog.dart';
import 'snippet_avatar.dart';

/// Floating spotlight-style snippet picker: search and group filter. One that
/// needs arguments asks for them in [showSnippetArgsDialog]. Choosing a
/// snippet always runs it - there is no insert-for-review mode to pick
/// between. The command palette's tools grid is a separate, anchored menu
/// (`command_palette_menu.dart`); this is just what its "Insert snippet"
/// tile opens into.
///
/// Unlike `showDialog`, this route captures no ambient theme, and its only
/// caller is the terminal's action dock, so the panel is put back into the
/// session's colours here.
Future<void> showSnippetSpotlight(
  BuildContext context, {
  required void Function(Snippet snippet, Map<String, String> argValues)
  onSelect,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: Translations.of(context).commandPalette.insertSnippetTitle,
    barrierColor: Colors.black54,
    transitionDuration: Duration(milliseconds: isDesktopPlatform ? 110 : 260),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.08),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
    pageBuilder: (ctx, _, _) =>
        TerminalSchemeTheme(child: SnippetPickerPanel(onSelect: onSelect)),
  );
}

class SnippetPickerPanel extends ConsumerStatefulWidget {
  const SnippetPickerPanel({super.key, required this.onSelect});

  final void Function(Snippet snippet, Map<String, String> argValues) onSelect;

  @override
  ConsumerState<SnippetPickerPanel> createState() => _SnippetPickerPanelState();
}

class _SnippetPickerPanelState extends ConsumerState<SnippetPickerPanel> {
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _query = '';
  String _selectedGroup = '';

  /// The row Enter runs, moved with the arrow keys; back to the top whenever
  /// the list changes under it.
  int _cursor = 0;
  final _cursorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<Snippet> _filteredSnippets(List<Snippet> snippets) {
    final q = _query.trim().toLowerCase();
    final groups = <String>{for (final s in snippets) s.group};
    final filterByGroup = groups.length > 1 && _selectedGroup.isNotEmpty;
    return snippets.where((s) {
      if (filterByGroup && s.group != _selectedGroup) {
        return false;
      }
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.command.toLowerCase().contains(q) ||
          s.group.toLowerCase().contains(q);
    }).toList();
  }

  /// Cancelling the arguments dialog comes back here, to the list.
  Future<void> _select(Snippet snippet) async {
    unawaited(HapticFeedback.selectionClick());
    var values = const <String, String>{};
    if (snippet.placeholders.isNotEmpty) {
      final entered = await showSnippetArgsDialog(context, snippet);
      if (entered == null || !mounted) return;
      values = entered;
    }
    widget.onSelect(snippet, values);
    Navigator.of(context).pop();
  }

  void _submitSelected() {
    final snippets = _filteredSnippets(ref.read(snippetsProvider));
    if (snippets.isEmpty) return;
    unawaited(_select(snippets[math.min(_cursor, snippets.length - 1)]));
  }

  /// Up and down move the cursor through the list while the field keeps the
  /// focus, so typing and picking never take turns.
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
    final count = _filteredSnippets(ref.read(snippetsProvider)).length;
    if (count == 0) return KeyEventResult.handled;
    setState(() => _cursor = (math.min(_cursor, count - 1) + step) % count);
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

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final snippets = ref.watch(snippetsProvider);
    final groups = <String>{for (final s in snippets) s.group}.toList()..sort();
    final profileGroups = ref.watch(profileGroupsProvider);
    final groupsWithColour = [
      for (final name in groups)
        profileGroups.where((g) => isSameGroup(g.name, name)).firstOrNull ??
            ProfileGroup(name: name),
    ];
    final filteredSnippets = _filteredSnippets(snippets);
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final safePadding = mediaQuery.padding;
    final availableHeight = math.max(
      0.0,
      screenSize.height - keyboardInset - safePadding.vertical - 48,
    );
    final resultsHeight = filteredSnippets.isEmpty
        ? 150.0
        : filteredSnippets.take(5).fold(0.0, (sum, _) => sum + 68.0);
    final showGroupFilter = groups.length > 1;
    final chromeHeight = showGroupFilter ? 178.0 : 136.0;
    final preferredHeight = (chromeHeight + resultsHeight).clamp(300.0, 560.0);
    final cardHeight = math.min(preferredHeight, availableHeight);
    final cardWidth = math.min(520.0, math.max(0.0, screenSize.width - 56));

    return AnimatedPadding(
      duration: AppTheme.motionSlow,
      curve: AppTheme.interactiveCurve,
      padding: EdgeInsets.fromLTRB(
        28,
        safePadding.top + 24,
        28,
        keyboardInset + safePadding.bottom + 24,
      ),
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          elevation: 12,
          shadowColor: Colors.black54,
          child: AnimatedContainer(
            duration: AppTheme.motionSlow,
            curve: AppTheme.interactiveCurve,
            width: cardWidth,
            height: cardHeight,
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: context.colors.surfaceBorderStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.commandPalette.insertSnippetTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(PhosphorIconsRegular.x),
                        tooltip: t.common.close,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onFieldKey,
                    child: TextField(
                      key: const ValueKey('snippetSearchField'),
                      controller: _searchCtrl,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(
                        fontSize: 15,
                        color: context.colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: t.commandPalette.searchHintSnippets,
                        hintStyle: TextStyle(
                          color: context.colors.textTertiary,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          PhosphorIconsRegular.magnifyingGlass,
                          size: 18,
                        ),
                        filled: true,
                        fillColor: context.colors.surfaceCard,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          borderSide: BorderSide(
                            color: context.colors.surfaceBorder,
                          ),
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        _query = v;
                        _cursor = 0;
                      }),
                      onSubmitted: (_) => _submitSelected(),
                    ),
                  ),
                ),
                if (showGroupFilter) ...[
                  const SizedBox(height: 10),
                  GroupFilterChips(
                    groups: groupsWithColour,
                    selected: _selectedGroup,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onChanged: (group) => setState(() {
                      _selectedGroup = group;
                      _cursor = 0;
                    }),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: _buildSnippetsList(t, snippets, filteredSnippets),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSnippetsList(
    Translations t,
    List<Snippet> allSnippets,
    List<Snippet> filtered,
  ) {
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            allSnippets.isEmpty
                ? t.commandPalette.empty
                : t.commandPalette.noResults,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textTertiary, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, index) => _buildTile(
        t,
        filtered[index],
        selected: index == math.min(_cursor, filtered.length - 1),
      ),
    );
  }

  /// The "Enter to run" hint is shown only on the [selected] row, the one
  /// Enter would actually act on.
  Widget _buildTile(Translations t, Snippet snippet, {bool selected = false}) {
    return Container(
      key: selected ? _cursorKey : null,
      decoration: BoxDecoration(
        color: context.colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: selected
              ? context.colors.primaryMuted
              : context.colors.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () => unawaited(_select(snippet)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const SnippetAvatar(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                snippet.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                            if (selected)
                              _EnterHint(label: t.commandPalette.enterToRun),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snippet.command.split('\n').first,
                          overflow: TextOverflow.ellipsis,
                          style: context.colors.monoStyle.copyWith(
                            fontSize: 12,
                            color: context.colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge marking the row the Enter key would act on.
class _EnterHint extends StatelessWidget {
  const _EnterHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.primaryHighlight,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.keyReturn,
            size: 12,
            color: context.colors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

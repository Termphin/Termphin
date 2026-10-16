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
import '../groups/group_filter_chips.dart';
import '../terminal/terminal_scheme_theme.dart';
import '../ui/app_card.dart';
import '../ui/app_search_field.dart';
import 'snippet_args_dialog.dart';

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
    barrierColor: AppTheme.scrim,
    transitionDuration: AppTheme.motionMedium,
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

  void _submitFirst() {
    final snippets = _filteredSnippets(ref.read(snippetsProvider));
    if (snippets.isNotEmpty) unawaited(_select(snippets.first));
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
        AppTheme.space24,
        safePadding.top + AppTheme.space24,
        AppTheme.space24,
        keyboardInset + safePadding.bottom + AppTheme.space24,
      ),
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          elevation: 12,
          shadowColor: AppTheme.scrim,
          child: AnimatedContainer(
            duration: AppTheme.motionSlow,
            curve: AppTheme.interactiveCurve,
            width: cardWidth,
            height: cardHeight,
            padding: const EdgeInsets.only(top: AppTheme.space6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: context.colors.surfaceBorderStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space16,
                    AppTheme.space12,
                    AppTheme.space8,
                    AppTheme.space8,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space16,
                  ),
                  child: AppSearchField(
                    key: const ValueKey('snippetSearchField'),
                    controller: _searchCtrl,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    dense: true,
                    textInputAction: TextInputAction.search,
                    hint: t.commandPalette.searchHintSnippets,
                    clearTooltip: t.common.clearSearch,
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (_) => _submitFirst(),
                  ),
                ),
                if (showGroupFilter) ...[
                  const SizedBox(height: AppTheme.space10),
                  GroupFilterChips(
                    groups: groupsWithColour,
                    selected: _selectedGroup,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space16,
                    ),
                    onChanged: (group) =>
                        setState(() => _selectedGroup = group),
                  ),
                ],
                const SizedBox(height: AppTheme.space8),
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
          padding: const EdgeInsets.all(AppTheme.space24),
          child: Text(
            allSnippets.isEmpty
                ? t.commandPalette.empty
                : t.commandPalette.noResults,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textTertiary,
              fontSize: AppTheme.font13,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space12,
        AppTheme.space4,
        AppTheme.space12,
        AppTheme.space16,
      ),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.space6),
      itemBuilder: (_, index) =>
          _buildTile(t, filtered[index], first: index == 0),
    );
  }

  /// The "Enter to run" hint is shown only on the row Enter would actually
  /// act on.
  Widget _buildTile(Translations t, Snippet snippet, {bool first = false}) {
    return AppCard(
      onTap: () => unawaited(_select(snippet)),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space10,
      ),
      child: Row(
        children: [
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
                          fontSize: AppTheme.font14,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (first) _EnterHint(label: t.commandPalette.enterToRun),
                  ],
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  snippet.command.split('\n').first,
                  overflow: TextOverflow.ellipsis,
                  style: context.colors.monoStyle.copyWith(
                    fontSize: AppTheme.font12,
                    color: context.colors.textTertiary,
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

/// Badge marking the row the Enter key would act on.
class _EnterHint extends StatelessWidget {
  const _EnterHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: AppTheme.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space8,
        vertical: AppTheme.space2,
      ),
      decoration: BoxDecoration(
        color: context.colors.primaryHighlight,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.keyReturn,
            size: AppTheme.icon12,
            color: context.colors.primary,
          ),
          const SizedBox(width: AppTheme.space4),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTheme.font10,
              fontWeight: FontWeight.w600,
              color: context.colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

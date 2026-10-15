import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../models/snippet.dart';
import '../../providers/groups_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/group_filter_chips.dart';
import '../../widgets/ui/group_picker_sheet.dart';
import '../../widgets/ui/group_section_header.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/selection_action_bar.dart';
import '../search/global_search_launcher.dart';
import 'snippet_form_screen.dart';
import 'snippet_run_screen.dart';
import 'snippet_runs_screen.dart';

enum _SnippetAction { edit, copy, duplicate, delete }

class SnippetsScreen extends ConsumerStatefulWidget {
  const SnippetsScreen({super.key});

  @override
  ConsumerState<SnippetsScreen> createState() => _SnippetsScreenState();
}

/// A group with no snippets draws no section: an empty header would only
/// say that it is empty, and the group is still on the groups screen with
/// the snippet form's picker still offering it. The group filter chips,
/// though, only list groups that have a snippet, since a chip leading to a
/// certain empty list is a dead end.
class _SnippetsScreenState extends ConsumerState<SnippetsScreen> {
  String _selectedGroup = '';
  final Set<String> _selectedIds = <String>{};

  List<Snippet> _filter(List<Snippet> snippets) {
    return snippets
        .where(
          (snippet) =>
              _selectedGroup.isEmpty ||
              isSameGroup(snippet.group, _selectedGroup),
        )
        .toList();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _onSnippetTap(Snippet snippet) {
    if (_selectedIds.isNotEmpty) {
      _toggleSelection(snippet.id);
    } else {
      _run(context, snippet);
    }
  }

  void _onSnippetLongPress(Snippet snippet) {
    HapticFeedback.lightImpact();
    _toggleSelection(snippet.id);
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  /// Reported from the push rather than from the screen, which is a
  /// [ConsumerWidget] with no `initState` to hang it off.
  Future<void> _openRuns(BuildContext context) {
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.snippetRuns));
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SnippetRunsScreen()));
  }

  Future<void> _run(BuildContext context, Snippet snippet) async {
    final batchId = await showSnippetRunScreen(context, snippet);
    if (batchId == null || !context.mounted) return;
    await _openRuns(context);
  }

  Future<void> _copyCommand(Snippet snippet) async {
    await copyToClipboard(
      context,
      snippet.command,
      message: Translations.of(context).snippets.commandCopied,
    );
  }

  Future<void> _duplicate(Snippet snippet) async {
    final t = Translations.of(context);
    final name = t.snippets.duplicateSuffix(name: snippet.name);
    await ref
        .read(snippetsProvider.notifier)
        .duplicateSnippet(snippet, name: name);
    if (!mounted) return;
    AppNotifications.success(context, t.snippets.duplicated(name: name));
  }

  /// Asked for here rather than inside the editor, so deleting no longer means
  /// opening the snippet first.
  Future<void> _delete(Snippet snippet) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.snippets.deleteTitle,
      message: t.snippets.deleteConfirm(name: snippet.name),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref.read(snippetsProvider.notifier).deleteSnippet(snippet.id);
    if (!mounted) return;
    if (_selectedIds.remove(snippet.id)) {
      setState(() {});
    }
    AppNotifications.success(context, t.snippets.deleted(name: snippet.name));
  }

  Future<void> _moveSelected() async {
    final allSnippets = ref.read(snippetsProvider);
    final selectedSnippets = allSnippets
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    if (selectedSnippets.isEmpty) return;

    final profileGroups = ref.read(profileGroupsProvider);
    final groupsList = [...profileGroups];
    if (!groupsList.any(
      (g) => isSameGroup(g.name, GroupStorage.defaultGroup),
    )) {
      groupsList.insert(0, const ProfileGroup(name: GroupStorage.defaultGroup));
    }

    final allSameGroup = selectedSnippets.every(
      (s) => isSameGroup(s.group, selectedSnippets.first.group),
    );
    final currentGroup = allSameGroup
        ? resolveGroupName(
                selectedSnippets.first.group,
                groupsList.map((g) => g.name),
              ) ??
              selectedSnippets.first.group
        : null;

    final targetGroup = await showGroupPickerSheet(
      context,
      groups: groupsList,
      current: currentGroup,
    );
    if (targetGroup == null || !mounted) return;

    final count = selectedSnippets.length;
    final notifier = ref.read(snippetsProvider.notifier);
    for (final snippet in selectedSnippets) {
      await notifier.updateSnippet(
        snippet,
        name: snippet.name,
        command: snippet.command,
        group: targetGroup,
        defaults: snippet.defaults,
      );
    }

    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
    });

    final t = Translations.of(context);
    final groupName = isSameGroup(targetGroup, GroupStorage.defaultGroup)
        ? t.groups.general
        : targetGroup;
    AppNotifications.success(
      context,
      t.selection.moved(n: count, count: count, group: groupName),
    );
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.selection.deleteTitle(n: count, count: count),
      message: t.selection.deleteConfirm,
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final idsToDelete = _selectedIds.toList();
    final notifier = ref.read(snippetsProvider.notifier);
    for (final id in idsToDelete) {
      await notifier.deleteSnippet(id);
    }

    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
    });

    AppNotifications.success(
      context,
      t.selection.deleted(n: count, count: count),
    );
  }

  void _onAction(_SnippetAction action, Snippet snippet) {
    switch (action) {
      case _SnippetAction.edit:
        showSnippetFormScreen(context, existing: snippet);
      case _SnippetAction.copy:
        unawaited(_copyCommand(snippet));
      case _SnippetAction.duplicate:
        unawaited(_duplicate(snippet));
      case _SnippetAction.delete:
        unawaited(_delete(snippet));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final snippets = ref.watch(snippetsProvider);
    final visibleSnippets = _filter(snippets);
    final profileGroups = ref.watch(profileGroupsProvider);

    final groupsList = [...profileGroups];
    if (!groupsList.any(
      (g) => isSameGroup(g.name, GroupStorage.defaultGroup),
    )) {
      groupsList.insert(0, const ProfileGroup(name: GroupStorage.defaultGroup));
    }

    final Map<String, List<Snippet>> snippetsByGroup = {
      for (final g in groupsList) g.name: <Snippet>[],
    };
    for (final snippet in visibleSnippets) {
      final matchingGroup = groupsList
          .where((g) => isSameGroup(g.name, snippet.group))
          .firstOrNull;
      final targetGroup = matchingGroup?.name ?? GroupStorage.defaultGroup;
      snippetsByGroup[targetGroup]!.add(snippet);
    }

    final displayGroups = groupsList
        .where((g) => (snippetsByGroup[g.name]?.isNotEmpty ?? false))
        .toList();
    final populatedGroups = groupsList
        .where((g) => snippets.any((s) => isSameGroup(s.group, g.name)))
        .toList();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: LargeTitleScaffold(
        title: t.snippets.title,
        resizeToAvoidBottomInset: false,
        actions: [
          IconButton(
            tooltip: t.snippets.runsTitle,
            onPressed: () => _openRuns(context),
            icon: const Icon(PhosphorIconsRegular.playCircle),
          ),
        ],
        bodyBuilder: (context, scrollController, gutter) {
          final scrollView = CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverPadding(
                padding: gutter,
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: LargeTitleHeader(
                        title: t.snippets.title,
                        subtitle: t.snippets.subtitle,
                      ),
                    ),
                    if (snippets.isNotEmpty) ...[
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: GlobalSearchLauncher(
                            heroTag: 'globalSearch-snippets',
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: GroupFilterChips(
                          groups: populatedGroups,
                          selected: _selectedGroup,
                          onChanged: (group) =>
                              setState(() => _selectedGroup = group),
                        ),
                      ),
                    ],
                    if (snippets.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyStatePanel(
                          icon: PhosphorIconsFill.codeBlock,
                          title: t.snippets.emptyTitle,
                          subtitle: t.snippets.emptySubtitle,
                          action: Tooltip(
                            message: t.snippets.newTitle,
                            child: ElevatedButton.icon(
                              onPressed: () => showSnippetFormScreen(context),
                              icon: const Icon(
                                PhosphorIconsRegular.plus,
                                size: 18,
                              ),
                              label: Text(t.snippets.newTitle),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      for (final (i, group) in displayGroups.indexed) ...[
                        GroupSectionHeader.sliver(
                          group: group,
                          count: snippetsByGroup[group.name]?.length ?? 0,
                          onAdd: () => showSnippetFormScreen(
                            context,
                            initialGroup: group.name,
                          ),
                          addTooltip: t.snippets.newTitle,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            i == 0 ? 4 : 16,
                            16,
                            4,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          sliver: SliverList.separated(
                            itemCount: snippetsByGroup[group.name]!.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final snippet =
                                  snippetsByGroup[group.name]![index];
                              return _SnippetCard(
                                snippet: snippet,
                                selected: _selectedIds.contains(snippet.id),
                                selectionMode: _selectedIds.isNotEmpty,
                                onTap: () => _onSnippetTap(snippet),
                                onLongPress: () => _onSnippetLongPress(snippet),
                                onAction: (action) =>
                                    _onAction(action, snippet),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          );

          return SelectionActionHost(
            bar: _selectedIds.isEmpty
                ? null
                : SelectionActionBar(
                    count: _selectedIds.length,
                    onMove: _moveSelected,
                    onDelete: _deleteSelected,
                    onClear: _clearSelection,
                    onSelectAll:
                        visibleSnippets.isNotEmpty &&
                            visibleSnippets.any(
                              (s) => !_selectedIds.contains(s.id),
                            )
                        ? () {
                            setState(() {
                              _selectedIds.addAll(
                                visibleSnippets.map((s) => s.id),
                              );
                            });
                          }
                        : null,
                  ),
            child: scrollView,
          );
        },
      ),
    );
  }
}

/// One snippet in the list.
///
/// Tapping runs it. Everything that only shapes the snippet - editing,
/// copying, duplicating, deleting - is behind the overflow menu, the same way
/// a machine's card carries its own, rather than as loose icon buttons that
/// each claim a quarter of the row.
class _SnippetCard extends StatelessWidget {
  const _SnippetCard({
    required this.snippet,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final Snippet snippet;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<_SnippetAction> onAction;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: context.colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: AnimatedContainer(
        duration: AppTheme.interactiveDuration,
        decoration: BoxDecoration(
          color: SelectionStyle.fill(
            context,
            context.colors.surfaceElevated,
            selected: selected,
          ),
          borderRadius: radius,
          border: Border.fromBorderSide(
            SelectionStyle.side(context, selected: selected),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectionMode) ...[
                  SelectionCheck(selected: selected, size: 22),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snippet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.itemTitle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        snippet.command,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.monoSmall.copyWith(
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (selectionMode)
                  const SizedBox(width: 40)
                else
                  AppActionDropdown<_SnippetAction>(
                    tooltip: t.snippets.moreActions,
                    iconSize: 20,
                    iconColor: context.colors.textTertiary,
                    buttonSize: 40,
                    width: 220,
                    items: [
                      DropdownItem(
                        value: _SnippetAction.edit,
                        intrinsicHeight: true,
                        child: AppDropdownItem(
                          icon: PhosphorIconsRegular.pencilSimple,
                          label: t.common.edit,
                        ),
                      ),
                      DropdownItem(
                        value: _SnippetAction.copy,
                        intrinsicHeight: true,
                        child: AppDropdownItem(
                          icon: PhosphorIconsRegular.copy,
                          label: t.snippets.copyCommand,
                        ),
                      ),
                      DropdownItem(
                        value: _SnippetAction.duplicate,
                        intrinsicHeight: true,
                        child: AppDropdownItem(
                          icon: PhosphorIconsRegular.copySimple,
                          label: t.common.duplicate,
                        ),
                      ),
                      DropdownItem(
                        value: _SnippetAction.delete,
                        intrinsicHeight: true,
                        child: AppDropdownItem(
                          icon: PhosphorIconsRegular.trash,
                          label: t.common.delete,
                          color: context.colors.error,
                        ),
                      ),
                    ],
                    onSelected: onAction,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

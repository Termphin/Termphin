import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../models/snippet.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippet_runs_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/profile_sort.dart';
import '../../widgets/groups/group_filter_chips.dart';
import '../../widgets/profiles/profile_avatar.dart';
import '../../widgets/profiles/profile_pick_card.dart';
import '../../widgets/profiles/profile_search_field.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';

/// Picks the machines a snippet should run on, collecting any
/// `{{placeholder}}` values once for the whole batch.
///
/// Returns the batch id so the caller can open the run window on it.
///
/// A screen rather than a bottom sheet: this is a task with inputs that ends
/// in one commit action, which is the shape [showPortForwardingRuleSheet]
/// already has - header with a way back, scrolling body, and the button that
/// finishes it pinned under a divider. As a sheet it was the one surface in
/// the app that looked like nothing else in it, and a multi-select over every
/// machine had to happen inside 70% of the window.
Future<String?> showSnippetRunScreen(BuildContext context, Snippet snippet) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => SnippetRunScreen(snippet: snippet),
    ),
  );
}

class SnippetRunScreen extends ConsumerStatefulWidget {
  const SnippetRunScreen({super.key, required this.snippet});

  final Snippet snippet;

  @override
  ConsumerState<SnippetRunScreen> createState() => _SnippetRunScreenState();
}

class _SnippetRunScreenState extends ConsumerState<SnippetRunScreen> {
  final _selected = <String>{};
  final _argControllers = <String, TextEditingController>{};
  final _searchController = TextEditingController();
  String _search = '';
  String _selectedGroup = '';
  ProfileSort _sort = ProfileSort.recentlyUsed;

  @override
  void initState() {
    super.initState();
    for (final name in widget.snippet.placeholders) {
      _argControllers[name] = TextEditingController(
        text: widget.snippet.defaultFor(name),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _argControllers.values) {
      controller.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  /// Filtered by the search box and put in the order the sort menu asks for -
  /// the same box and the same orders as the home screen, so the machine at
  /// the top here is the machine at the top there.
  List<SshProfile> _visible(List<SshProfile> profiles) {
    final query = _search.trim().toLowerCase();
    final matching = profiles.where((profile) {
      if (_selectedGroup.isNotEmpty && profile.group != _selectedGroup) {
        return false;
      }
      if (query.isEmpty) return true;
      return profile.name.toLowerCase().contains(query) ||
          profile.host.toLowerCase().contains(query) ||
          profile.username.toLowerCase().contains(query) ||
          profile.group.toLowerCase().contains(query);
    }).toList();
    return sortProfiles(matching, _sort);
  }

  /// The batch is created before any host is dialled, so the run window can
  /// open on it right away and fill itself in as the connections land.
  void _start() {
    final profiles = ref
        .read(profilesProvider)
        .where((profile) => _selected.contains(profile.id))
        .toList();
    if (profiles.isEmpty) return;
    final batchId = ref
        .read(snippetRunsProvider.notifier)
        .start(
          snippet: widget.snippet,
          profiles: profiles,
          argValues: {
            for (final entry in _argControllers.entries)
              entry.key: entry.value.text,
          },
        );
    Navigator.of(context).pop(batchId);
  }

  /// Acts on what is on screen, not on everything saved - a filtered list that
  /// silently picked the machines it is hiding would be a trap.
  void _toggleAll(List<SshProfile> visible) {
    final ids = visible.map((profile) => profile.id).toSet();
    setState(() {
      if (ids.every(_selected.contains)) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final profiles = ref.watch(profilesProvider);
    final profileGroups = ref.watch(profileGroupsProvider);
    final groups = profiles.map((p) => p.group).toSet().toList()..sort();
    final groupsWithColour = [
      for (final name in groups)
        profileGroups.where((g) => isSameGroup(g.name, name)).firstOrNull ??
            ProfileGroup(name: name),
    ];
    final visible = _visible(profiles);
    final allVisibleSelected =
        visible.isNotEmpty &&
        visible.every((profile) => _selected.contains(profile.id));

    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      body: SafeArea(
        child: ContentGutter(
          builder: (context, gutter) => Column(
            children: [
              Padding(
                padding: gutter,
                child: _Header(
                  title: t.snippets.runTitle,
                  subtitle: widget.snippet.name,
                ),
              ),
              const SizedBox(height: AppTheme.space8),
              const AppDivider(),
              Expanded(
                child: profiles.isEmpty
                    ? EmptyStatePanel(
                        icon: PhosphorIconsFill.terminalWindow,
                        title: t.snippets.pickMachines,
                        subtitle: t.snippets.pickMachinesEmpty,
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          AppTheme.space20,
                          AppTheme.space16,
                          AppTheme.space20,
                          MediaQuery.viewInsetsOf(context).bottom +
                              AppTheme.space24,
                        ).add(gutter),
                        children: [
                          if (widget.snippet.placeholders.isNotEmpty) ...[
                            SectionHeader(
                              t.snippets.argumentsTitle,
                              hint: t.snippets.runArgumentsHint,
                            ),
                            const SizedBox(height: AppTheme.space10),
                            for (final name in widget.snippet.placeholders) ...[
                              AppFormField(
                                key: ValueKey('snippetRunArg:$name'),
                                controller: _argControllers[name]!,
                                label: name,
                                icon: PhosphorIconsFill.bracketsCurly,
                                monospace: true,
                              ),
                              const SizedBox(height: AppTheme.space10),
                            ],
                            const SizedBox(height: AppTheme.space14),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: SectionHeader(
                                  t.snippets.pickMachines,
                                  hint: t.snippets.pickMachinesSelected(
                                    count: _selected.length,
                                    total: profiles.length,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: visible.isEmpty
                                    ? null
                                    : () => _toggleAll(visible),
                                child: Text(
                                  allVisibleSelected
                                      ? t.common.clearSelection
                                      : t.common.selectAll,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.space10),
                          ProfileSearchField(
                            controller: _searchController,
                            sort: _sort,
                            onChanged: (value) =>
                                setState(() => _search = value),
                            onSortChanged: (value) =>
                                setState(() => _sort = value),
                          ),
                          if (groups.length > 1) ...[
                            const SizedBox(height: AppTheme.space10),
                            GroupFilterChips(
                              groups: groupsWithColour,
                              selected: _selectedGroup,
                              padding: EdgeInsets.zero,
                              onChanged: (group) =>
                                  setState(() => _selectedGroup = group),
                            ),
                          ],
                          const SizedBox(height: AppTheme.space12),
                          if (visible.isEmpty)
                            EmptyStateHint(
                              icon: PhosphorIconsRegular.magnifyingGlass,
                              text: t.profiles.noResults(query: _search),
                            )
                          else
                            for (final profile in visible) ...[
                              _MachineRow(
                                key: ValueKey('snippetRunHost:${profile.id}'),
                                profile: profile,
                                selected: _selected.contains(profile.id),
                                onTap: () => setState(() {
                                  if (!_selected.remove(profile.id)) {
                                    _selected.add(profile.id);
                                  }
                                }),
                              ),
                              const SizedBox(height: AppTheme.space10),
                            ],
                        ],
                      ),
              ),
              const AppDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space12,
                  AppTheme.space20,
                  AppTheme.space16,
                ).add(gutter),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                    ),
                    onPressed: _selected.isEmpty ? null : _start,
                    child: Text(t.snippets.runNow(count: _selected.length)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back arrow and title, the same header the tunnel editor draws.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space8,
        AppTheme.space16,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: Translations.of(context).common.back,
            icon: Icon(
              PhosphorIconsRegular.arrowLeft,
              size: AppTheme.icon20,
              color: context.colors.textSecondary,
            ),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppTheme.space2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.colors.uiSmall.copyWith(
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

/// One machine to run on.
///
/// Deliberately the card the machine already has everywhere else - same fill,
/// same 42px avatar, same title and subtitle styles - so picking one here
/// reads as the same object as managing it on the home screen. Being picked
/// shows in the accent edge and the tick, not in a different card.
class _MachineRow extends ConsumerWidget {
  const _MachineRow({
    super.key,
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final SshProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anonymize = ref.watch(anonymizeProvider);
    final name = anonymize ? IdentityAnonymizer.name(profile.id) : profile.name;
    final username = anonymize
        ? IdentityAnonymizer.username(profile.id)
        : profile.username;
    final host = anonymize ? IdentityAnonymizer.host(profile.id) : profile.host;

    return ProfilePickCard(
      leading: ProfileAvatar(
        iconName: profile.iconName,
        colorHex: profile.colorHex,
        size: 42,
      ),
      title: name,
      subtitle: '$username@$host:${profile.port}',
      selected: selected,
      showUnselectedIndicator: true,
      onTap: onTap,
    );
  }
}

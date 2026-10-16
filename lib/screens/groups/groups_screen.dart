import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../models/ssh_key.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/snippets_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../services/storage/group_storage.dart';
import '../../services/storage/ssh_key_storage.dart';
import '../../theme/theme.dart';
import '../../widgets/groups/group_dot.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import 'group_form_screen.dart';

/// Screen allowing the user to view, reorder, create, edit, and delete groups.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

/// There is no plus button in the app bar: the "add group" row already says
/// the same thing where the eye lands, and two controls for one action
/// read as two actions. `General` always has a row, since it is the only
/// group a fresh install has and its colour stays editable. Each row can be
/// dragged by holding anywhere on it - there is no separate handle to
/// withhold - so `General` reorders like any other group; it is guaranteed
/// to exist, not to sit first.
class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  late SshKeyStorage _keyStorage;
  List<SshKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _keyStorage = ref.read(sshKeyStorageProvider);
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keys = await _keyStorage.loadKeys();
    if (mounted) {
      setState(() => _keys = keys);
    }
  }

  /// The row being carried. `ReorderableListView` otherwise hands the child
  /// back unchanged, so a held row would look identical to a resting one and
  /// the gesture would read as nothing having happened.
  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.03 * t,
          child: Material(
            color: context.colors.surfaceElevated,
            elevation: 6 * t,
            shadowColor: context.colors.backgroundPrimary,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _createGroup() async {
    await showGroupFormScreen(context);
    if (mounted) {
      await _loadKeys();
    }
  }

  Future<void> _editGroup(ProfileGroup group) async {
    await showGroupFormScreen(context, existing: group);
    if (mounted) {
      await _loadKeys();
    }
  }

  Future<void> _deleteGroup(String name) async {
    final t = Translations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: t.groups.deleteTitle,
      message: t.groups.deleteConfirm(name: name),
      confirmLabel: t.common.delete,
      destructive: true,
    );

    if (!confirmed) return;
    await ref.read(profileGroupsProvider.notifier).deleteGroup(name);
    if (mounted) {
      await _loadKeys();
    }
    await HapticFeedback.heavyImpact();
  }

  String _formatCount(
    Translations t, {
    required int machineCount,
    required int keyCount,
    required int snippetCount,
  }) {
    final parts = <String>[];
    if (machineCount > 0) {
      parts.add(t.groups.countMachines(n: machineCount, count: machineCount));
    }
    if (keyCount > 0) {
      parts.add(t.groups.countKeys(n: keyCount, count: keyCount));
    }
    if (snippetCount > 0) {
      parts.add(t.groups.countSnippets(n: snippetCount, count: snippetCount));
    }
    if (parts.isEmpty) {
      return t.groups.groupEmpty;
    }
    return parts.join(' \u00b7 ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final groups = ref.watch(profileGroupsProvider);
    final profiles = ref.watch(profilesProvider);
    final snippets = ref.watch(snippetsProvider);

    final knownGroups = groups.map((g) => g.name).toSet();

    return LargeTitleScaffold(
      title: t.groups.title,
      bodyBuilder: (context, scrollController, gutter) => CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: gutter,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: LargeTitleHeader(
                    title: t.groups.title,
                    subtitle: t.groups.subtitle,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space16,
                    AppTheme.space8,
                    AppTheme.space16,
                    AppTheme.space16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppCard.fields(
                      children: [
                        InkWell(
                          onTap: _createGroup,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.space16,
                              vertical: AppTheme.space14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  PhosphorIconsRegular.plus,
                                  size: AppTheme.icon18,
                                  color: context.colors.primary,
                                ),
                                const SizedBox(width: AppTheme.space12),
                                Text(
                                  t.groups.newGroup,
                                  style: context.colors.uiStyle.copyWith(
                                    fontSize: AppTheme.font14,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppTheme.space16,
                    0,
                    AppTheme.space16,
                    groups.length > 1 ? AppTheme.space8 : AppTheme.space32,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppCard(
                      clipChild: true,
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: groups.length,
                        onReorderStart: (_) => HapticFeedback.selectionClick(),
                        proxyDecorator: _liftedRow,
                        onReorderItem: (oldIndex, newIndex) {
                          ref
                              .read(profileGroupsProvider.notifier)
                              .reorder(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final isDefault =
                              group.name == GroupStorage.defaultGroup;
                          final machineCount = profiles
                              .where(
                                (p) =>
                                    p.group == group.name ||
                                    (isDefault &&
                                        !knownGroups.contains(p.group)),
                              )
                              .length;
                          final keyCount = _keys
                              .where(
                                (k) =>
                                    k.group == group.name ||
                                    (isDefault &&
                                        !knownGroups.contains(k.group)),
                              )
                              .length;
                          final snippetCount = snippets
                              .where(
                                (s) =>
                                    s.group == group.name ||
                                    (isDefault &&
                                        !knownGroups.contains(s.group)),
                              )
                              .length;
                          final countText = _formatCount(
                            t,
                            machineCount: machineCount,
                            keyCount: keyCount,
                            snippetCount: snippetCount,
                          );

                          return Column(
                            key: ValueKey(group.name),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDelayedDragStartListener(
                                index: index,
                                child: InkWell(
                                  onTap: () => _editGroup(group),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.space12,
                                      vertical: AppTheme.space10,
                                    ),
                                    child: Row(
                                      children: [
                                        GroupDot(
                                          colorHex: group.colorHex,
                                          size: 10,
                                        ),
                                        const SizedBox(width: AppTheme.space12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      group.name,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.titleMedium,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isDefault) ...[
                                                    const SizedBox(
                                                      width: AppTheme.space8,
                                                    ),
                                                    AppBadge(
                                                      t.groups.defaultBadge,
                                                      tone: BadgeTone.accent,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(
                                                height: AppTheme.space2,
                                              ),
                                              Text(
                                                countText,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isDefault)
                                          IconButton(
                                            tooltip: t.common.delete,
                                            iconSize: AppTheme.icon18,
                                            visualDensity:
                                                VisualDensity.compact,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            icon: const Icon(
                                              PhosphorIconsRegular.trash,
                                            ),
                                            onPressed: () =>
                                                _deleteGroup(group.name),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (index < groups.length - 1) const AppDivider(),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (groups.length > 1)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space20,
                      0,
                      AppTheme.space20,
                      AppTheme.space32,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        t.groups.reorderHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

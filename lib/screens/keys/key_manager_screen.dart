import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_key.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../services/storage/group_storage.dart';
import '../../services/storage/ssh_key_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/platform_info.dart';
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
import 'key_form_screen.dart';

class KeyManagerScreen extends ConsumerStatefulWidget {
  const KeyManagerScreen({super.key});

  @override
  ConsumerState<KeyManagerScreen> createState() => _KeyManagerScreenState();
}

/// A group with no keys draws no section: an empty header would only say
/// that it is empty. The group still shows up on the groups screen, and the
/// key form's group picker still offers it.
class _KeyManagerScreenState extends ConsumerState<KeyManagerScreen> {
  final _scrollController = ScrollController();
  String _selectedGroup = '';
  final Set<String> _selectedKeyIds = <String>{};
  List<SshKey> _keys = [];
  bool _loading = true;
  bool _showCollapsedTitle = false;
  static const double _collapseTitleOffset = 56;

  bool get _isSelectionMode => _selectedKeyIds.isNotEmpty;
  SshKeyStorage get _storage => ref.read(sshKeyStorageProvider);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadKeys();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedKeyIds.contains(id)) {
        _selectedKeyIds.remove(id);
      } else {
        _selectedKeyIds.add(id);
      }
    });
  }

  List<SshKey> _filter(List<SshKey> keys, Iterable<String> knownGroups) {
    if (_selectedGroup.isEmpty) return keys;
    return keys.where((key) {
      final keyGroup =
          resolveGroupName(key.group, knownGroups) ?? GroupStorage.defaultGroup;
      return isSameGroup(keyGroup, _selectedGroup);
    }).toList();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > _collapseTitleOffset;
    if (shouldShow == _showCollapsedTitle) return;
    setState(() => _showCollapsedTitle = shouldShow);
  }

  Future<void> _loadKeys({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    final keys = await _storage.loadKeys();
    if (mounted) {
      setState(() {
        _keys = keys;
        _loading = false;
      });
    }
  }

  Future<void> _deleteKey(SshKey key) async {
    final t = Translations.of(context);
    final machines = ref
        .read(profilesProvider)
        .where((p) => p.sshKeyId == key.id)
        .toList();

    final String title;
    final String message;
    final String confirmLabel;

    if (machines.isEmpty) {
      title = t.keys.deleteTitle;
      message = t.keys.deleteConfirm(name: key.name);
      confirmLabel = t.common.delete;
    } else {
      title = t.keys.inUseTitle;
      message = [
        t.keys.inUseBody(n: machines.length, count: machines.length),
        ...machines.map((p) => p.name),
        t.keys.deleteConfirm(name: key.name),
      ].join('\n');
      confirmLabel = t.keys.deleteAnyway;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: true,
    );
    if (!confirmed) return;

    await _storage.deleteKey(key.id);
    if (mounted) {
      setState(() => _keys = _keys.where((k) => k.id != key.id).toList());
      AppNotifications.success(context, t.keys.deleted(name: key.name));
    }
  }

  Future<void> _copyPublicKey(SshKey key) async {
    await copyToClipboard(
      context,
      key.publicKeyOpenSSH,
      message: Translations.of(context).profiles.keyCopied(name: key.name),
    );
  }

  Future<void> _moveSelectedKeys() async {
    final t = Translations.of(context);
    final groups = ref.read(profileGroupsProvider);
    final selectedKeys = _keys
        .where((k) => _selectedKeyIds.contains(k.id))
        .toList();
    if (selectedKeys.isEmpty) return;

    final groupsOfSelected = selectedKeys.map((k) => k.group).toSet();
    final currentGroup = groupsOfSelected.length == 1
        ? groupsOfSelected.first
        : null;

    final picked = await showGroupPickerSheet(
      context,
      groups: groups,
      current: currentGroup,
    );
    if (picked == null || !mounted) return;

    final count = selectedKeys.length;
    for (final key in selectedKeys) {
      await _storage.updateKey(key.copyWith(group: picked));
    }

    await _loadKeys(showLoading: false);
    if (!mounted) return;
    setState(() => _selectedKeyIds.clear());
    final groupDisplay = picked == GroupStorage.defaultGroup
        ? t.groups.general
        : picked;
    AppNotifications.success(
      context,
      t.selection.moved(n: count, count: count, group: groupDisplay),
    );
  }

  Future<void> _deleteSelectedKeys() async {
    final t = Translations.of(context);
    final selectedIds = _selectedKeyIds.toSet();
    if (selectedIds.isEmpty) return;

    final machines = ref
        .read(profilesProvider)
        .where((p) => p.sshKeyId != null && selectedIds.contains(p.sshKeyId))
        .toList();

    final count = selectedIds.length;
    final String title;
    final String message;
    final String confirmLabel;

    if (machines.isEmpty) {
      title = t.selection.deleteTitle(n: count, count: count);
      message = t.selection.deleteConfirm;
      confirmLabel = t.common.delete;
    } else {
      title = t.selection.inUseTitle;
      message = [
        t.selection.keysInUseBody(n: machines.length, count: machines.length),
        ...machines.map((p) => p.name),
        t.selection.deleteConfirm,
      ].join('\n');
      confirmLabel = t.selection.deleteAnyway;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    for (final id in selectedIds) {
      await _storage.deleteKey(id);
    }
    await _loadKeys(showLoading: false);
    if (!mounted) return;
    setState(() => _selectedKeyIds.clear());
    AppNotifications.success(
      context,
      t.selection.deleted(n: count, count: count),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sshKeysRevisionProvider, (_, _) {
      _loadKeys(showLoading: false);
    });
    final t = Translations.of(context);
    ref.watch(profilesProvider);
    final groups = ref.watch(profileGroupsProvider);
    final collapsed = isWideLayout(context) || _showCollapsedTitle;
    final knownGroupNames = {for (final g in groups) g.name};
    final visibleKeys = _filter(_keys, knownGroupNames);
    final populatedGroups = groups
        .where(
          (g) => _keys.any((k) {
            final eff =
                resolveGroupName(k.group, knownGroupNames) ??
                GroupStorage.defaultGroup;
            return isSameGroup(eff, g.name);
          }),
        )
        .toList();
    final Map<String, List<SshKey>> keysByGroup = {
      for (final g in groups) g.name: <SshKey>[],
    };

    for (final key in visibleKeys) {
      final targetGroup = knownGroupNames.contains(key.group)
          ? key.group
          : GroupStorage.defaultGroup;
      if (keysByGroup.containsKey(targetGroup)) {
        keysByGroup[targetGroup]!.add(key);
      } else {
        keysByGroup.putIfAbsent(targetGroup, () => []).add(key);
      }
    }

    final displayGroups = groups
        .where((g) => (keysByGroup[g.name] ?? const []).isNotEmpty)
        .toList();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          shape: collapsed
              ? Border(
                  bottom: BorderSide(
                    color: context.colors.surfaceBorder,
                    width: 1,
                  ),
                )
              : const Border(),
          title: AnimatedOpacity(
            duration: AppTheme.interactiveDuration,
            opacity: collapsed ? 1 : 0,
            child: Text(
              t.keys.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        body: SelectionActionHost(
          bar: _isSelectionMode
              ? SelectionActionBar(
                  count: _selectedKeyIds.length,
                  onMove: _moveSelectedKeys,
                  onDelete: _deleteSelectedKeys,
                  onClear: () => setState(() => _selectedKeyIds.clear()),
                  onSelectAll:
                      visibleKeys.isNotEmpty &&
                          visibleKeys.every(
                            (k) => _selectedKeyIds.contains(k.id),
                          )
                      ? null
                      : () {
                          setState(() {
                            _selectedKeyIds.addAll(
                              visibleKeys.map((k) => k.id),
                            );
                          });
                        },
                )
              : null,
          child: SafeArea(
            top: false,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ContentGutter(
                    builder: (context, gutter) => CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: gutter,
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: LargeTitleHeader(
                                  title: t.keys.title,
                                  subtitle: t.keys.subtitle,
                                ),
                              ),
                              if (_keys.isNotEmpty) ...[
                                const SliverPadding(
                                  padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                                  sliver: SliverToBoxAdapter(
                                    child: GlobalSearchLauncher(
                                      heroTag: 'globalSearch-keys',
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
                              if (_keys.isEmpty)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _buildEmptyState(),
                                )
                              else ...[
                                for (final (i, group)
                                    in displayGroups.indexed) ...[
                                  GroupSectionHeader.sliver(
                                    group: group,
                                    count: keysByGroup[group.name]?.length ?? 0,
                                    onAdd: () async {
                                      await showKeyFormScreen(
                                        context,
                                        initialGroup: group.name,
                                      );
                                      if (mounted) {
                                        await _loadKeys(showLoading: false);
                                      }
                                    },
                                    addTooltip: t.keys.addKey,
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      i == 0 ? 4 : 16,
                                      16,
                                      4,
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      12,
                                    ),
                                    sliver: SliverList.separated(
                                      itemCount:
                                          keysByGroup[group.name]!.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final key =
                                            keysByGroup[group.name]![index];
                                        final selected = _selectedKeyIds
                                            .contains(key.id);
                                        return _KeyTile(
                                          sshKey: key,
                                          selected: selected,
                                          isSelectionMode: _isSelectionMode,
                                          onTap: () {
                                            if (_isSelectionMode) {
                                              _toggleSelection(key.id);
                                            }
                                          },
                                          onLongPress: () {
                                            if (!_isSelectionMode) {
                                              setState(() {
                                                _selectedKeyIds.add(key.id);
                                              });
                                            } else {
                                              _toggleSelection(key.id);
                                            }
                                          },
                                          onDelete: () => _deleteKey(key),
                                          onEdit: () async {
                                            await showKeyFormScreen(
                                              context,
                                              existing: key,
                                            );
                                            if (mounted) {
                                              await _loadKeys(
                                                showLoading: false,
                                              );
                                            }
                                          },
                                          onCopyPublicKey: () =>
                                              _copyPublicKey(key),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = Translations.of(context);
    return EmptyStatePanel(
      icon: PhosphorIconsFill.key,
      title: t.keys.emptyTitle,
      subtitle: t.keys.emptySubtitle,
      action: Tooltip(
        message: t.keys.addKey,
        child: ElevatedButton.icon(
          onPressed: () async {
            await showKeyFormScreen(context);
            if (mounted) await _loadKeys(showLoading: false);
          },
          icon: const Icon(PhosphorIconsRegular.plus, size: 18),
          label: Text(t.keys.addKey),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
        ),
      ),
    );
  }
}

/// A single key row. The trailing actions stay in the layout but hidden
/// (`Visibility.maintain`) during selection, so the row does not reflow as
/// selection starts.
class _KeyTile extends StatelessWidget {
  const _KeyTile({
    required this.sshKey,
    required this.selected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onEdit,
    required this.onCopyPublicKey,
  });

  final SshKey sshKey;
  final bool selected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onCopyPublicKey;

  String get _typeLabel => sshKey.keyType.label;

  Color _typeColor(BuildContext context) => switch (sshKey.keyType) {
    SshKeyType.ed25519 => context.colors.success,
    SshKeyType.rsa2048 || SshKeyType.rsa4096 => context.colors.primary,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: AppTheme.interactiveDuration,
        decoration: BoxDecoration(
          color: SelectionStyle.fill(
            context,
            context.colors.surfaceCard,
            selected: selected,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.fromBorderSide(
            SelectionStyle.side(context, selected: selected),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isSelectionMode) ...[
                SelectionCheck(selected: selected, size: 22),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          sshKey.name,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _typeColor(context).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXs,
                            ),
                            border: Border.all(
                              color: _typeColor(
                                context,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            _typeLabel,
                            style: TextStyle(
                              color: _typeColor(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sshKey.formattedDate,
                      style: TextStyle(
                        color: context.colors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Visibility.maintain(
                visible: !isSelectionMode,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(PhosphorIconsFill.copy, size: 20),
                      color: context.colors.primary,
                      tooltip: Translations.of(context).keys.copyPublicKey,
                      onPressed: onCopyPublicKey,
                    ),
                    Builder(
                      builder: (ctx) {
                        final t = Translations.of(ctx);
                        return AppActionDropdown<String>(
                          iconSize: 20,
                          buttonSize: 40,
                          iconColor: context.colors.textSecondary,
                          width: 220,
                          items: [
                            DropdownItem(
                              value: 'copy',
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsFill.copy,
                                label: t.keys.copyPublicKey,
                              ),
                            ),
                            DropdownItem(
                              value: 'edit',
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsFill.pencilSimple,
                                label: t.common.edit,
                              ),
                            ),
                            DropdownItem(
                              value: 'delete',
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsFill.trash,
                                label: t.common.delete,
                                color: context.colors.error,
                              ),
                            ),
                          ],
                          onSelected: (v) {
                            if (v == 'copy') onCopyPublicKey();
                            if (v == 'edit' || v == 'rename') onEdit();
                            if (v == 'delete') onDelete();
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

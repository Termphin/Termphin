import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_key.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../services/app/app_commands.dart';
import '../../services/platform/local_ssh_keys.dart';
import '../../services/storage/group_storage.dart';
import '../../services/storage/ssh_key_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../../utils/platform_info.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/clipboard_and_links.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/context_menu.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/group_filter_chips.dart';
import '../../widgets/ui/group_picker_sheet.dart';
import '../../widgets/ui/group_section_header.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/list_key_navigation.dart';
import '../../widgets/ui/list_section_header.dart';
import '../../widgets/ui/selection_action_bar.dart';
import '../../widgets/ui/text_input_dialog.dart';
import '../../widgets/window/page_bar.dart';
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
  List<LocalSshKey> _localKeys = [];
  final Set<String> _importingLocal = <String>{};
  bool _loading = true;
  bool _showCollapsedTitle = false;
  static const double _collapseTitleOffset = 56;

  bool get _isSelectionMode => _selectedKeyIds.isNotEmpty;
  SshKeyStorage get _storage => ref.read(sshKeyStorageProvider);

  late final VoidCallback _unregisterEscape;

  /// Esc on a desktop drops the selection, as a click on its X does.
  bool _clearSelectionOnEscape() {
    if (!mounted || _selectedKeyIds.isEmpty) return false;
    setState(() => _selectedKeyIds.clear());
    return true;
  }

  @override
  void initState() {
    super.initState();
    _unregisterEscape = AppCommands.instance.registerEscape(
      _clearSelectionOnEscape,
    );
    _scrollController.addListener(_onScroll);
    _loadKeys();
  }

  @override
  void dispose() {
    _unregisterEscape();
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

  /// Also looks in the user's own `.ssh` folder where there is one, for the
  /// keys there that are not in the app yet - listed above the rest, each an
  /// Import button away.
  Future<void> _loadKeys({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    final keys = await _storage.loadKeys();
    final local = platformHas(PlatformFeature.localSshFolder)
        ? await ref.read(localSshKeysProvider).scan(imported: keys)
        : const <LocalSshKey>[];
    if (mounted) {
      setState(() {
        _keys = keys;
        _localKeys = local;
        _loading = false;
      });
    }
  }

  /// Imports [local] into the group being looked at, asking for its
  /// passphrase first if it has one. Returns whether it went in.
  ///
  /// The passphrase only reads the key's public half and is not kept, as in
  /// the key form: the profile that uses the key asks for it again.
  Future<bool> _importLocalKey(LocalSshKey local, {bool notify = true}) async {
    final t = Translations.of(context);
    String? passphrase;
    if (local.encrypted) {
      passphrase = await showTextInputDialog(
        context,
        title: t.keys.localPassphraseTitle(name: local.name),
        confirmLabel: t.keys.localImport,
        labelText: t.keys.keyPassphraseLabel,
        obscureText: true,
      );
      if (passphrase == null || passphrase.isEmpty || !mounted) return false;
    }
    setState(() => _importingLocal.add(local.name));
    try {
      await _storage.importFromPem(
        local.name,
        local.pem,
        group: _selectedGroup.isEmpty
            ? GroupStorage.defaultGroup
            : _selectedGroup,
        passphrase: passphrase,
      );
      if (!mounted) return true;
      if (notify) {
        AppNotifications.success(
          context,
          t.keys.importSuccess(name: local.name),
        );
      }
      return true;
    } on KeyImportException catch (error) {
      if (mounted) {
        AppNotifications.error(context, switch (error.reason) {
          KeyImportFailure.wrongPassphrase => t.keys.importWrongPassphrase,
          KeyImportFailure.passphraseRequired =>
            t.keys.importPassphraseRequired,
        });
      }
      return false;
    } catch (error) {
      if (mounted) {
        AppNotifications.error(context, t.keys.importFailed(error: '$error'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _importingLocal.remove(local.name));
    }
  }

  Future<void> _importOneLocalKey(LocalSshKey local) async {
    await _importLocalKey(local);
    if (mounted) await _loadKeys(showLoading: false);
  }

  /// Every key found, the ones with a passphrase asking for theirs in turn.
  Future<void> _importAllLocalKeys() async {
    final t = Translations.of(context);
    var imported = 0;
    for (final local in List.of(_localKeys)) {
      if (!mounted) return;
      if (await _importLocalKey(local, notify: false)) imported++;
    }
    if (!mounted) return;
    if (imported > 0) {
      AppNotifications.success(context, t.keys.localImportedCount(n: imported));
    }
    await _loadKeys(showLoading: false);
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
        appBar: DesktopPageHeader.replacesAppBar(context)
            ? null
            : AppBar(
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
        body: DesktopPageHeader(
          title: t.keys.title,
          child: ListKeyNavigation(
            child: SelectionActionHost(
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
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        12,
                                      ),
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
                                        onChanged: (group) => setState(
                                          () => _selectedGroup = group,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_localKeys.isNotEmpty)
                                    SliverToBoxAdapter(
                                      child: _LocalKeysSection(
                                        keys: _localKeys,
                                        importing: _importingLocal,
                                        onImport: _importOneLocalKey,
                                        onImportAll: _importAllLocalKeys,
                                      ),
                                    ),
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
                                        count:
                                            keysByGroup[group.name]?.length ??
                                            0,
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
                                            Future<void> edit() async {
                                              await showKeyFormScreen(
                                                context,
                                                existing: key,
                                              );
                                              if (mounted) {
                                                await _loadKeys(
                                                  showLoading: false,
                                                );
                                              }
                                            }

                                            return ContextMenuRegion(
                                              entries: () => [
                                                ContextMenuEntry(
                                                  label: t.contextMenu.edit,
                                                  icon: PhosphorIconsRegular
                                                      .pencilSimple,
                                                  onSelected: () =>
                                                      unawaited(edit()),
                                                ),
                                                ContextMenuEntry(
                                                  label: t.keys.copyPublicKey,
                                                  icon:
                                                      PhosphorIconsRegular.copy,
                                                  onSelected: () =>
                                                      _copyPublicKey(key),
                                                ),
                                                ContextMenuEntry(
                                                  label: t.contextMenu.select,
                                                  icon: PhosphorIconsRegular
                                                      .checkSquare,
                                                  onSelected: () =>
                                                      _toggleSelection(key.id),
                                                ),
                                                null,
                                                ContextMenuEntry(
                                                  label: t.contextMenu.delete,
                                                  icon: PhosphorIconsRegular
                                                      .trash,
                                                  destructive: true,
                                                  onSelected: () =>
                                                      _deleteKey(key),
                                                ),
                                              ],
                                              child: _KeyTile(
                                                sshKey: key,
                                                selected: selected,
                                                isSelectionMode:
                                                    _isSelectionMode,
                                                onTap: () {
                                                  if (_isSelectionMode ||
                                                      selectionModifierPressed) {
                                                    _toggleSelection(key.id);
                                                  }
                                                },
                                                onLongPress: () {
                                                  if (!_isSelectionMode) {
                                                    setState(() {
                                                      _selectedKeyIds.add(
                                                        key.id,
                                                      );
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
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                    SliverToBoxAdapter(
                                      child: SizedBox(
                                        height: _isSelectionMode
                                            ? SelectionActionBar.reservedHeight
                                            : 32,
                                      ),
                                    ),
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
                        _KeyTypeBadge(
                          label: _typeLabel,
                          color: _typeColor(context),
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

/// The keys found in the user's own `.ssh` folder that the app does not have
/// yet, each one click from being imported.
///
/// Laid out as one more group of the list it sits over - the same header
/// with a count, the same cards - so it reads as keys, not as a banner. What
/// tells it apart is what its rows offer: Import where a stored key has its
/// menu, and the path where a stored key has its date.
class _LocalKeysSection extends StatelessWidget {
  const _LocalKeysSection({
    required this.keys,
    required this.importing,
    required this.onImport,
    required this.onImportAll,
  });

  final List<LocalSshKey> keys;

  /// Names of the keys being imported right now, whose buttons wait.
  final Set<String> importing;
  final ValueChanged<LocalSshKey> onImport;
  final VoidCallback onImportAll;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final busy = importing.isNotEmpty;
    return Column(
      key: const ValueKey('localKeysSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListSectionHeader(
          title: t.keys.localTitle,
          count: keys.length,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          actions: [
            if (keys.length > 1)
              TextButton.icon(
                onPressed: busy ? null : onImportAll,
                icon: const Icon(PhosphorIconsRegular.downloadSimple, size: 16),
                label: Text(t.keys.localImportAll),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text(
            t.keys.localSubtitle,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              for (final (i, key) in keys.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                _LocalKeyTile(
                  localKey: key,
                  importing: importing.contains(key.name),
                  onImport: busy ? null : () => onImport(key),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A key waiting in `~/.ssh`, drawn as the stored keys under it are: the
/// same card, its name with what kind of key it is beside it, and under
/// that where it is. A lock says it will ask for a passphrase.
class _LocalKeyTile extends StatelessWidget {
  const _LocalKeyTile({
    required this.localKey,
    required this.importing,
    required this.onImport,
  });

  final LocalSshKey localKey;
  final bool importing;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final algorithm = localKey.algorithm;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: colors.surfaceBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        localKey.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (algorithm != null) ...[
                      const SizedBox(width: 8),
                      _KeyTypeBadge(
                        label: algorithm,
                        color: algorithm == 'ed25519'
                            ? colors.success
                            : colors.primary,
                      ),
                    ],
                    if (localKey.encrypted) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: t.keys.localEncrypted,
                        child: Icon(
                          PhosphorIconsRegular.lockKey,
                          size: 15,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  localKey.displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.monoStyle.copyWith(
                    color: colors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: ValueKey('importLocalKey-${localKey.name}'),
            onPressed: onImport,
            icon: importing
                ? SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(PhosphorIconsRegular.downloadSimple, size: 16),
            label: Text(t.keys.localImport),
          ),
        ],
      ),
    );
  }
}

/// The pill naming a key's algorithm, tinted with the colour that goes with
/// it - shared by a stored key's card and one still in `~/.ssh`.
class _KeyTypeBadge extends StatelessWidget {
  const _KeyTypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

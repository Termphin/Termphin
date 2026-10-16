import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../providers/groups_provider.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../utils/route_pop.dart';
import '../../widgets/groups/group_dot.dart';
import '../../widgets/profiles/profile_avatar.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';
import 'groups_screen.dart';

/// Opens the create/edit screen for [existing] (or a new group if null).
Future<ProfileGroup?> showGroupFormScreen(
  BuildContext context, {
  ProfileGroup? existing,
  bool showManageGroups = false,
}) {
  return Navigator.of(context).push<ProfileGroup>(
    MaterialPageRoute<ProfileGroup>(
      builder: (_) => GroupFormScreen(
        existing: existing,
        showManageGroups: showManageGroups,
      ),
      fullscreenDialog: true,
    ),
  );
}

/// Create/edit screen for a profile group.
///
/// The toolbar's manage-groups icon is the only way into the full group
/// list - reordering, deleting and creating happen there. The default
/// group's name field stays read-only but keeps a cursor, or typing looks
/// like the app is dropping keys. The "no colour" swatch's check icon uses
/// the text colour instead of white, since the swatch itself is filled
/// with the (light) field colour.
class GroupFormScreen extends ConsumerStatefulWidget {
  const GroupFormScreen({
    super.key,
    this.existing,
    this.showManageGroups = false,
  });

  final ProfileGroup? existing;
  final bool showManageGroups;

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  late final TextEditingController _nameCtrl;
  String? _selectedColorHex;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;
  bool get _isDefaultGroup =>
      widget.existing?.name.toLowerCase() ==
      GroupStorage.defaultGroup.toLowerCase();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    if (_isEditing) {
      _selectedColorHex = widget.existing?.colorHex;
    } else {
      final groups = ref.read(profileGroupsProvider);
      final usedColors = {
        for (final g in groups)
          if (g.colorHex != null) g.colorHex!.toUpperCase(),
      };
      ProfileAvatarColor? unused;
      for (final item in ProfileAvatarColor.colors) {
        if (!usedColors.contains(item.hex.toUpperCase())) {
          unused = item;
          break;
        }
      }
      _selectedColorHex = (unused ?? ProfileAvatarColor.colors.first).hex;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && !_isSaving;

  /// Saves the name and colour. Deselecting a colour swatch clears it
  /// explicitly via `clearColor`, since a null `colorHex` alone reads as
  /// "leave it alone".
  Future<void> _save() async {
    if (!_canSave) return;
    final name = _nameCtrl.text.trim();
    final t = Translations.of(context);
    final groups = ref.read(profileGroupsProvider);

    final collision = groups.any(
      (g) =>
          g.name.toLowerCase() == name.toLowerCase() &&
          (!_isEditing ||
              g.name.toLowerCase() != widget.existing!.name.toLowerCase()),
    );

    if (collision) {
      AppNotifications.error(context, t.groups.alreadyExists);
      return;
    }

    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);

    setState(() => _isSaving = true);

    try {
      final ProfileGroup resultGroup;
      if (!_isEditing) {
        await ref
            .read(profileGroupsProvider.notifier)
            .addGroup(name, colorHex: _selectedColorHex);
        resultGroup = ProfileGroup(name: name, colorHex: _selectedColorHex);
      } else {
        final targetName = _isDefaultGroup ? null : name;
        await ref
            .read(profileGroupsProvider.notifier)
            .updateGroup(
              widget.existing!.name,
              name: targetName,
              colorHex: _selectedColorHex,
              clearColor: _selectedColorHex == null,
            );
        resultGroup = ProfileGroup(
          name: _isDefaultGroup ? widget.existing!.name : name,
          colorHex: _selectedColorHex,
        );
      }

      if (!mounted) return;
      popRouteWithResult(navigator, route, resultGroup);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// The same delete the groups list offers, asked the same way: records in
  /// the group are moved to `General` rather than going with it. It lives
  /// here too, since this is where the user already is when they decide it
  /// was a bad idea - a trip to another screen is enough friction that
  /// people leave the group instead.
  Future<void> _delete() async {
    final t = Translations.of(context);
    final name = widget.existing!.name;
    final confirmed = await showConfirmDialog(
      context,
      title: t.groups.deleteTitle,
      message: t.groups.deleteConfirm(name: name),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);

    setState(() => _isSaving = true);
    await ref.read(profileGroupsProvider.notifier).deleteGroup(name);
    if (!mounted) return;
    popRouteWithResult(navigator, route, null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isEditing ? t.groups.editGroup : t.groups.newGroup,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: IconButton(
          tooltip: t.common.close,
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.showManageGroups)
            IconButton(
              tooltip: t.groups.manageGroups,
              icon: const Icon(PhosphorIconsRegular.slidersHorizontal),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GroupsScreen()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.space12),
            child: _isSaving
                ? const SizedBox(
                    width: AppTheme.icon20,
                    height: AppTheme.icon20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ListenableBuilder(
                    listenable: _nameCtrl,
                    builder: (context, _) => TextButton(
                      onPressed: _canSave ? _save : null,
                      child: Text(
                        t.common.save,
                        style: TextStyle(
                          color: _canSave
                              ? context.colors.primary
                              : context.colors.textTertiary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppTheme.font15,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => ListView(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space20,
              _isEditing ? AppTheme.space8 : AppTheme.space16,
              AppTheme.space20,
              AppTheme.space40,
            ).add(gutter),
            children: [
              _GroupPreview(
                name: _nameCtrl,
                colorHex: _selectedColorHex,
                isDefaultGroup: _isDefaultGroup,
              ),
              const SizedBox(height: AppTheme.space20),
              AppFormField(
                key: const ValueKey('groupNameField'),
                controller: _nameCtrl,
                label: t.groups.groupName,
                hint: t.groups.groupNameHint,
                icon: PhosphorIconsFill.folder,
                action: TextInputAction.done,
                autofocus: !_isEditing,
                readOnly: _isDefaultGroup,
                onSubmitted: (_) => _save(),
              ),
              if (_isDefaultGroup) ...[
                const SizedBox(height: AppTheme.space8),
                Text(
                  t.groups.defaultNameLocked,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppTheme.space24),
              SectionHeader(t.groups.colorLabel),
              const SizedBox(height: AppTheme.space12),
              Wrap(
                spacing: AppTheme.space10,
                runSpacing: AppTheme.space10,
                children: [
                  Tooltip(
                    message: t.groups.noColour,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColorHex = null;
                        });
                      },
                      child: AnimatedContainer(
                        duration: AppTheme.interactiveDuration,
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: context.colors.fieldFill,
                          shape: BoxShape.circle,
                          border: _selectedColorHex == null
                              ? Border.all(
                                  color: context.colors.textPrimary,
                                  width: 2.5,
                                )
                              : Border.all(
                                  color: context.colors.surfaceBorderStrong,
                                ),
                        ),
                        child: _selectedColorHex == null
                            ? Icon(
                                PhosphorIconsRegular.check,
                                size: AppTheme.icon16,
                                color: context.colors.textPrimary,
                              )
                            : null,
                      ),
                    ),
                  ),
                  ...ProfileAvatarColor.colors.map((item) {
                    final selected =
                        _selectedColorHex?.toUpperCase() ==
                        item.hex.toUpperCase();
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColorHex = item.hex;
                        });
                      },
                      child: AnimatedContainer(
                        duration: AppTheme.interactiveDuration,
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: item.color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: ProfileAvatarColor.onSwatch,
                                  width: 2.5,
                                )
                              : null,
                        ),
                        child: selected
                            ? const Icon(
                                PhosphorIconsRegular.check,
                                size: AppTheme.icon16,
                                color: ProfileAvatarColor.onSwatch,
                              )
                            : null,
                      ),
                    );
                  }),
                ],
              ),
              if (_isEditing && !_isDefaultGroup) ...[
                const SizedBox(height: AppTheme.space32),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _delete,
                  icon: const Icon(
                    PhosphorIconsRegular.trash,
                    size: AppTheme.icon18,
                  ),
                  label: Text(t.common.delete),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The group drawn the way a list screen draws it, above the fields that
/// change it.
class _GroupPreview extends StatelessWidget {
  const _GroupPreview({
    required this.name,
    required this.colorHex,
    required this.isDefaultGroup,
  });

  final TextEditingController name;
  final String? colorHex;
  final bool isDefaultGroup;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return ListenableBuilder(
      listenable: name,
      builder: (context, _) {
        final typed = name.text.trim();
        final label = isDefaultGroup
            ? t.groups.general
            : (typed.isEmpty ? t.groups.groupNameHint : typed);
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space16,
            vertical: AppTheme.space14,
          ),
          child: Row(
            children: [
              GroupDot(colorHex: colorHex, size: 10),
              const SizedBox(width: AppTheme.space10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: typed.isEmpty && !isDefaultGroup
                        ? context.colors.textTertiary
                        : context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/toolbar_layout.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_badge.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_divider.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/text_input_dialog.dart';
import 'toolbar_settings_screen.dart';

const _uuid = Uuid();

enum _ProfileAction { edit, rename, duplicate, delete }

/// The saved toolbar layouts, and which one the toolbar is drawing.
///
/// Sits in front of the editor rather than inside it: the editor always works
/// on the layout in use, so choosing one here is what decides what is being
/// edited - and what every open session is looking at.
class ToolbarProfilesScreen extends StatefulWidget {
  const ToolbarProfilesScreen({super.key});

  @override
  State<ToolbarProfilesScreen> createState() => _ToolbarProfilesScreenState();
}

/// There is no plus button in the app bar: the "new profile" row above the
/// list is the only way in, the same row the groups screen puts above its
/// own list - a screen whose whole point is making another one should say
/// so where the eye already is.
class _ToolbarProfilesScreenState extends State<ToolbarProfilesScreen> {
  @override
  void initState() {
    super.initState();
    toolbarSettings.profiles.addListener(_onChanged);
  }

  @override
  void dispose() {
    toolbarSettings.profiles.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _displayName(Translations t, ToolbarProfile profile) =>
      profile.name.isEmpty ? t.settings.toolbarProfileDefault : profile.name;

  /// Hands the toolbar to [profile] and stays here - the row reads as a radio
  /// button, so tapping one has to be the pick, not a trip to the editor.
  Future<void> _select(ToolbarProfile profile) async {
    if (profile.id == toolbarSettings.profiles.value.activeId) return;
    await activateToolbarProfile(profile.id);
  }

  /// Opens the editor on [profile], leaving the toolbar where it is.
  ///
  /// The editor works on the profile it is handed, so editing one no longer
  /// means switching to it - picking is what the row's tap is for.
  Future<void> _edit(ToolbarProfile profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ToolbarSettingsScreen(profileId: profile.id),
      ),
    );
  }

  Future<String?> _askForName(String title, String initial) async {
    final t = Translations.of(context);
    final name = await showTextInputDialog(
      context,
      title: title,
      confirmLabel: t.common.save,
      initialValue: initial,
      labelText: t.settings.toolbarProfileNameLabel,
    );
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Starts the new profile empty, not as a copy of the default: "new" here
  /// means a grid to fill, and anyone who wanted the default keys can
  /// duplicate that layout instead. It is also created without being
  /// switched to - handing the toolbar an empty grid would strip the keys
  /// off every open session before a single one had been placed.
  Future<void> _create() async {
    final t = Translations.of(context);
    final profiles = toolbarSettings.profiles.value;
    final name = await _askForName(
      t.settings.toolbarProfileNew,
      t.settings.toolbarProfileNewName(number: profiles.profiles.length + 1),
    );
    if (name == null || !mounted) return;
    final created = ToolbarProfile(
      id: _uuid.v4(),
      name: name,
      layout: ToolbarLayout.blank,
    );
    await saveToolbarProfiles(profiles.added(created, activate: false));
    if (!mounted) return;
    await _edit(created);
  }

  Future<void> _rename(ToolbarProfile profile) async {
    final t = Translations.of(context);
    final name = await _askForName(
      t.settings.toolbarProfileRenameTitle,
      _displayName(t, profile),
    );
    if (name == null) return;
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.withProfile(profile.copyWith(name: name)),
    );
  }

  Future<void> _duplicate(ToolbarProfile profile) async {
    final t = Translations.of(context);
    final copy = ToolbarProfile(
      id: _uuid.v4(),
      name: t.snippets.duplicateSuffix(name: _displayName(t, profile)),
      layout: profile.layout,
    );
    await saveToolbarProfiles(
      toolbarSettings.profiles.value.added(copy, activate: false),
    );
  }

  /// Deleting the profile in use hands the toolbar to whatever is left.
  Future<void> _delete(ToolbarProfile profile) async {
    final t = Translations.of(context);
    if (toolbarSettings.profiles.value.profiles.length <= 1) {
      AppNotifications.info(context, t.settings.toolbarProfileDeleteLast);
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.toolbarProfileDeleteTitle,
      message: t.settings.toolbarProfileDeleteConfirm(
        name: _displayName(t, profile),
      ),
      confirmLabel: t.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final next = toolbarSettings.profiles.value.removed(profile.id);
    await saveToolbarProfiles(next);
    if (profile.id == toolbarSettings.profiles.value.activeId) return;
    await activateToolbarProfile(next.activeId);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final profiles = toolbarSettings.profiles.value;

    return LargeTitleScaffold(
      title: t.settings.toolbarProfiles,
      bodyBuilder: (context, scrollController, gutter) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space16,
          0,
          AppTheme.space16,
          AppTheme.space32,
        ).add(gutter),
        children: [
          LargeTitleHeader(
            title: t.settings.toolbarProfiles,
            subtitle: t.settings.toolbarProfilesSubtitle,
            padding: const EdgeInsets.fromLTRB(
              0,
              AppTheme.space24,
              0,
              AppTheme.space8,
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          AppCard.fields(
            children: [
              InkWell(
                onTap: _create,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
                        t.settings.toolbarProfileNew,
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
          const SizedBox(height: AppTheme.space12),
          AppCard.fields(
            children: [
              for (final (index, profile) in profiles.profiles.indexed) ...[
                if (index > 0) const AppDivider(),
                _ProfileRow(
                  profile: profile,
                  name: _displayName(t, profile),
                  active: profile.id == profiles.activeId,
                  onTap: () => _select(profile),
                  onAction: (action) {
                    switch (action) {
                      case _ProfileAction.edit:
                        _edit(profile);
                      case _ProfileAction.rename:
                        _rename(profile);
                      case _ProfileAction.duplicate:
                        _duplicate(profile);
                      case _ProfileAction.delete:
                        _delete(profile);
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.name,
    required this.active,
    required this.onTap,
    required this.onAction,
  });

  final ToolbarProfile profile;
  final String name;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<_ProfileAction> onAction;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final layout = profile.layout;
    final keys = layout.order.where((id) => id.isNotEmpty).length;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space14,
          AppTheme.space10,
          AppTheme.space6,
          AppTheme.space10,
        ),
        child: Row(
          children: [
            Icon(
              active
                  ? PhosphorIconsFill.radioButton
                  : PhosphorIconsRegular.circle,
              size: AppTheme.icon18,
              color: active
                  ? context.colors.primary
                  : context.colors.textTertiary,
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.colors.itemTitle,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: AppTheme.space8),
                        AppBadge(
                          t.settings.toolbarProfileActive.toUpperCase(),
                          tone: BadgeTone.quiet,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppTheme.space2),
                  Text(
                    t.settings.toolbarProfileSummary(
                      count: keys,
                      columns: layout.columns,
                      rows: layout.rows,
                      pages: layout.pages,
                    ),
                    style: context.colors.uiSmall.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            AppActionDropdown<_ProfileAction>(
              iconSize: AppTheme.icon18,
              buttonSize: 40,
              iconColor: context.colors.textTertiary,
              width: 220,
              items: [
                DropdownItem(
                  value: _ProfileAction.edit,
                  intrinsicHeight: true,
                  child: AppDropdownItem(
                    icon: PhosphorIconsRegular.gridFour,
                    label: t.common.edit,
                  ),
                ),
                DropdownItem(
                  value: _ProfileAction.rename,
                  intrinsicHeight: true,
                  child: AppDropdownItem(
                    icon: PhosphorIconsRegular.pencilSimple,
                    label: t.common.rename,
                  ),
                ),
                DropdownItem(
                  value: _ProfileAction.duplicate,
                  intrinsicHeight: true,
                  child: AppDropdownItem(
                    icon: PhosphorIconsRegular.copySimple,
                    label: t.common.duplicate,
                  ),
                ),
                DropdownItem(
                  value: _ProfileAction.delete,
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
    );
  }
}

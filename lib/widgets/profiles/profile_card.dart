import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../theme/theme.dart';
import '../ui/app_dropdown.dart';
import '../ui/selection_action_bar.dart';
import 'profile_avatar.dart';

enum _ProfileCardAction { edit, loadSessions, delete }

/// A profile row with name, address and session status, plus an edit/load/
/// delete menu unless the row is in selection mode.
///
/// Its border skips the top edge shared with the session rows stitched
/// below it, unless selected, when it closes its own outline. The loading
/// spinner moves here because the menu the load was started from is already
/// closed, and its cancel action guards against a machine that never
/// answers. In selection mode the menu is replaced by blank space so a tap
/// only toggles the row.
class ProfileCard extends ConsumerWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.onTap,
    required this.onEdit,
    required this.onLoadSessions,
    required this.onDelete,
    this.onCancelLoadSessions,
    this.isLoadingSessions = false,
    this.sessionsCheckedLabel,
    this.isActive = false,
    this.attachedBelow = false,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final SshProfile profile;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onLoadSessions;
  final VoidCallback onDelete;

  /// Stops this machine's load. Null while nothing is in flight.
  final VoidCallback? onCancelLoadSessions;
  final bool isLoadingSessions;

  /// When the server session list below was last refreshed, e.g. "Checked
  /// 3m ago" - null until the user has loaded sessions at least once, so a
  /// list that was never checked doesn't claim to be current.
  final String? sessionsCheckedLabel;
  final bool isActive;

  /// Session rows are stitched underneath, so the card keeps its bottom edge
  /// square and the two read as one block.
  final bool attachedBelow;
  final VoidCallback? onLongPress;
  final bool selected;

  /// Some row on the screen is selected, so this one only toggles.
  final bool selectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = attachedBelow
        ? const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd))
        : BorderRadius.circular(AppTheme.radiusMd);
    final anonymize = ref.watch(anonymizeProvider);
    final displayName = anonymize
        ? IdentityAnonymizer.name(profile.id)
        : profile.name;
    final displayUsername = anonymize
        ? IdentityAnonymizer.username(profile.id)
        : profile.username;
    final displayHost = anonymize
        ? IdentityAnonymizer.host(profile.id)
        : profile.host;
    final t = Translations.of(context);

    final side = SelectionStyle.side(context, selected: selected);
    return Material(
      color: context.colors.surfaceElevated.invisible,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          color: SelectionStyle.fill(
            context,
            context.colors.surfaceElevated,
            selected: selected,
          ),
          borderRadius: radius,
          border: Border(
            top: side,
            left: side,
            right: side,
            bottom: attachedBelow && !selected ? BorderSide.none : side,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                SelectionCheck(
                  selected: selected,
                  size: 42,
                  child: ProfileAvatar(
                    iconName: profile.iconName,
                    colorHex: profile.colorHex,
                    isActive: isActive,
                    size: 42,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.itemTitle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$displayUsername@$displayHost:${profile.port}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.colors.uiStyle,
                      ),
                      if (isLoadingSessions) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            SizedBox.square(
                              dimension: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: context.colors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                t.session.loadingServerSessions,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.colors.uiSmall.copyWith(
                                  color: context.colors.textTertiary,
                                ),
                              ),
                            ),
                            if (onCancelLoadSessions != null) ...[
                              const SizedBox(width: 6),
                              InkResponse(
                                key: const ValueKey('cancelLoadSessions'),
                                onTap: onCancelLoadSessions,
                                radius: 14,
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Text(
                                    t.session.stopLoading,
                                    style: context.colors.uiSmall.copyWith(
                                      color: context.colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ] else if (sessionsCheckedLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          sessionsCheckedLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.colors.uiSmall.copyWith(
                            color: context.colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (selectionMode)
                  const SizedBox(width: 40)
                else
                  AppActionDropdown<_ProfileCardAction>(
                    tooltip: t.profiles.moreActions,
                    iconSize: 20,
                    iconColor: context.colors.textTertiary,
                    buttonSize: 40,
                    width: 220,
                    items: [
                      DropdownItem(
                        value: _ProfileCardAction.edit,
                        intrinsicHeight: true,
                        child: AppDropdownItem(
                          icon: PhosphorIconsRegular.pencilSimple,
                          label: t.common.edit,
                        ),
                      ),
                      DropdownItem(
                        value: _ProfileCardAction.loadSessions,
                        intrinsicHeight: true,
                        enabled: !isLoadingSessions,
                        child: isLoadingSessions
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(t.session.loadSessions),
                                ],
                              )
                            : AppDropdownItem(
                                icon: PhosphorIconsRegular.cloudArrowDown,
                                label: t.session.loadSessions,
                              ),
                      ),
                      DropdownItem(
                        value: _ProfileCardAction.delete,
                        intrinsicHeight: true,
                        child: AppDropdownItem(
                          icon: PhosphorIconsRegular.trash,
                          label: t.common.delete,
                          color: context.colors.error,
                        ),
                      ),
                    ],
                    onSelected: (action) {
                      switch (action) {
                        case _ProfileCardAction.edit:
                          onEdit();
                        case _ProfileCardAction.loadSessions:
                          onLoadSessions();
                        case _ProfileCardAction.delete:
                          onDelete();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

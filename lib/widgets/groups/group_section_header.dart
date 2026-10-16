import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../screens/groups/group_form_screen.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../ui/list_section_header.dart';
import 'group_dot.dart';

/// The load-sessions run outlives the tap by a round trip per machine, so
/// its button becomes the progress *and* the way out of it while running.
/// The edit button edits *this* group, which is why every header carries
/// one rather than a single button opening the whole group list - that
/// would be the same button repeated.
class GroupSectionHeader extends StatelessWidget {
  const GroupSectionHeader({
    super.key,
    required this.group,
    required this.count,
    required this.onAdd,
    required this.addTooltip,
    this.onLoadSessions,
    this.onCancelLoadSessions,
    this.isLoadingSessions = false,
    this.padding,
  });

  final ProfileGroup group;
  final int count;
  final VoidCallback onAdd;
  final String addTooltip;

  /// Fetches the server-side sessions of every machine in the group - the
  /// per-machine action run across the whole section.
  final VoidCallback? onLoadSessions;

  /// Stops a run in flight. The spinner is the button: a load that cannot be
  /// called off is a section held hostage by one machine that will not answer.
  final VoidCallback? onCancelLoadSessions;
  final bool isLoadingSessions;
  final EdgeInsetsGeometry? padding;

  static Widget sliver({
    Key? key,
    required ProfileGroup group,
    required int count,
    required VoidCallback onAdd,
    required String addTooltip,
    VoidCallback? onLoadSessions,
    VoidCallback? onCancelLoadSessions,
    bool isLoadingSessions = false,
    EdgeInsetsGeometry? padding,
  }) {
    return SliverToBoxAdapter(
      key: key,
      child: GroupSectionHeader(
        group: group,
        count: count,
        onAdd: onAdd,
        addTooltip: addTooltip,
        onLoadSessions: onLoadSessions,
        onCancelLoadSessions: onCancelLoadSessions,
        isLoadingSessions: isLoadingSessions,
        padding: padding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return ListSectionHeader(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupDot(colorHex: group.colorHex, size: 8),
          const SizedBox(width: AppTheme.space8),
          Text(
            group.name == GroupStorage.defaultGroup
                ? t.groups.general
                : group.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      count: count,
      actions: [
        if (onLoadSessions != null)
          ListSectionHeader.action(
            key: const ValueKey('groupLoadSessionsButton'),
            tooltip: isLoadingSessions
                ? t.session.stopLoading
                : t.session.loadGroupSessions,
            icon: isLoadingSessions
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.square(
                        dimension: AppTheme.icon18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.textTertiary,
                        ),
                      ),
                      const Icon(PhosphorIconsRegular.x, size: AppTheme.icon10),
                    ],
                  )
                : const Icon(PhosphorIconsRegular.cloudArrowDown),
            onPressed: isLoadingSessions
                ? onCancelLoadSessions
                : onLoadSessions,
            color: context.colors.textSecondary,
          ),
        ListSectionHeader.action(
          tooltip: t.groups.editGroup,
          icon: const Icon(PhosphorIconsRegular.pencilSimple),
          onPressed: () => showGroupFormScreen(context, existing: group),
          color: context.colors.textSecondary,
        ),
      ],
      onAdd: onAdd,
      addTooltip: addTooltip,
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppTheme.space16,
            vertical: AppTheme.space4,
          ),
    );
  }
}

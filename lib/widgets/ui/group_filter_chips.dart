import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../services/storage/group_storage.dart';
import 'group_dot.dart';
import 'tag_chip.dart';

/// The horizontal strip of group filters: "All", then one chip per group.
///
/// The sheets that pick a machine or a snippet each grew their own copy of this
/// row, and the list screens behind them had none at all - so the filter was
/// only ever available where the list was shortest. One widget, so a screen
/// filters the same way the sheet over it does.
///
/// [selected] is a group name, or the empty string for "All". The chips are
/// left out while there is one group or none: a filter offering a single
/// choice only takes the room a row of machines could have used.
///
/// Tapping the selected chip clears the filter, so the strip can be undone
/// without reaching back to "All".
class GroupFilterChips extends StatelessWidget {
  const GroupFilterChips({
    super.key,
    required this.groups,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  final List<ProfileGroup> groups;
  final String selected;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final showChips = groups.length > 1;
    if (!showChips) return const SizedBox.shrink();
    final t = Translations.of(context);

    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TagChip(
              label: t.groups.allGroups,
              selected: selected.isEmpty,
              onTap: () => onChanged(''),
            ),
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: TagChip(
                  label: group.name == GroupStorage.defaultGroup
                      ? t.groups.general
                      : group.name,
                  leading: GroupDot(colorHex: group.colorHex),
                  selected: selected == group.name,
                  onTap: () =>
                      onChanged(selected == group.name ? '' : group.name),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

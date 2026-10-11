import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../utils/profile_sort.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_search_field.dart';

/// The search box over a list of machines, with the sort menu in its trailing
/// slot.
///
/// One widget because a machine list is a machine list: the same box, the same
/// three orders and the same glyph for whichever one is in force, whether the
/// list is being managed on the home screen or picked from to run a snippet.
class ProfileSearchField extends StatelessWidget {
  const ProfileSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.sort,
    required this.onSortChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ProfileSort sort;
  final ValueChanged<ProfileSort> onSortChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return AppSearchField(
      controller: controller,
      focusNode: focusNode,
      hint: t.profiles.searchHint,
      clearTooltip: t.common.clearSearch,
      onChanged: onChanged,
      trailing: ProfileSortMenu(sort: sort, onChanged: onSortChanged),
    );
  }
}

/// The three orders a machine list can take, behind the glyph of whichever
/// one is in force. [boxSize] puts it in a square box of its own beside a
/// search box, drawn like one; otherwise it is a bare icon at the end of a field.
class ProfileSortMenu extends StatelessWidget {
  const ProfileSortMenu({
    super.key,
    required this.sort,
    required this.onChanged,
    this.boxSize,
  });

  final ProfileSort sort;
  final ValueChanged<ProfileSort> onChanged;
  final double? boxSize;

  static String _label(Translations t, ProfileSort sort) => switch (sort) {
    ProfileSort.recentlyUsed => t.profiles.sortRecent,
    ProfileSort.nameAZ => t.profiles.sortAZ,
    ProfileSort.nameZA => t.profiles.sortZA,
  };

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final icon = switch (sort) {
      ProfileSort.recentlyUsed => PhosphorIconsFill.clockCounterClockwise,
      ProfileSort.nameAZ => PhosphorIconsFill.sortAscending,
      ProfileSort.nameZA => PhosphorIconsFill.sortDescending,
    };
    return AppActionDropdown<ProfileSort>(
      icon: icon,
      iconSize: 18,
      buttonSize: 40,
      width: 200,
      direction: DropdownDirection.left,
      tooltip: t.profiles.sortMachines,
      items: ProfileSort.values.map((value) {
        return DropdownItem<ProfileSort>(
          value: value,
          intrinsicHeight: true,
          child: AppDropdownItem(
            label: _label(t, value),
            selected: value == sort,
          ),
        );
      }).toList(),
      onSelected: onChanged,
      child: boxSize != null
          ? Container(
              key: const ValueKey('profileSortButton'),
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: context.colors.fieldFill,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: context.colors.surfaceBorder),
              ),
              child: Icon(
                switch (sort) {
                  ProfileSort.recentlyUsed =>
                    PhosphorIconsRegular.clockCounterClockwise,
                  ProfileSort.nameAZ => PhosphorIconsRegular.sortAscending,
                  ProfileSort.nameZA => PhosphorIconsRegular.sortDescending,
                },
                size: 18,
                color: context.colors.textTertiary,
              ),
            )
          : null,
    );
  }
}

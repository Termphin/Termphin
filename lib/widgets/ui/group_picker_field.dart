import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../providers/groups_provider.dart';
import '../../screens/groups/group_form_screen.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import 'app_dropdown.dart';
import 'group_dot.dart';

/// Sentinel value for the "New group" entry. A dropdown picks a value, and
/// creating a group is an action, so it travels as a value no group can have.
const _newGroupValue = ' new-group';

/// Drawn as a text field rather than a card: it stands in a column of
/// `AppFormField`s, and a second shape in that column would read as a
/// different kind of control. The name of the field is the `SectionHeader`
/// above it, so there is none inside. A record can name a group the list
/// has not caught up with; that group is shown rather than snapping the
/// field to something the user did not choose. `selectedItemBuilder` ends
/// with an extra blank entry for the "New group" sentinel: it is never
/// shown, since the sentinel is handled before the field settles on it,
/// but the builder still has to match the item count.
class GroupPickerField extends ConsumerWidget {
  const GroupPickerField({
    super.key,
    required this.group,
    required this.onChanged,
  });

  final String group;
  final ValueChanged<String> onChanged;

  String _label(Translations t, String name) =>
      name == GroupStorage.defaultGroup ? t.groups.general : name;

  /// The package pops its own menu route *after* `onChanged` returns, so
  /// pushing the form straight away makes that pop land on the form instead:
  /// both routes then complete with the other's result type, and the menu is
  /// left on the stack with nothing able to dismiss it. Waiting a frame lets
  /// the menu close first.
  void _createGroup(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      final created = await showGroupFormScreen(
        context,
        showManageGroups: true,
      );
      if (created != null) onChanged(created.name);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final groups = ref.watch(profileGroupsProvider);
    final available = groups.any((g) => g.name == group)
        ? groups
        : [ProfileGroup(name: group), ...groups];

    return Container(
      decoration: BoxDecoration(
        color: context.colors.fieldFill,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.surfaceBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: DropdownButton2<String>(
        valueListenable: ValueNotifier(group),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        selectedItemBuilder: (context) => [
          for (final g in available)
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  GroupDot(colorHex: g.colorHex),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _label(t, g.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox.shrink(),
        ],
        onChanged: (value) {
          if (value == null) return;
          if (value == _newGroupValue) {
            _createGroup(context);
            return;
          }
          onChanged(value);
        },
        buttonStyleData: const ButtonStyleData(
          height: 44,
          padding: EdgeInsets.zero,
          elevation: 0,
        ),
        iconStyleData: IconStyleData(
          icon: Icon(
            PhosphorIconsFill.caretDown,
            size: 16,
            color: context.colors.textTertiary,
          ),
          iconSize: 16,
        ),
        dropdownStyleData: appDropdownStyle(
          context,
          maxHeight: 320,
          offset: const Offset(0, -6),
        ),
        menuItemStyleData: appDropdownItemStyle(
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        items: [
          for (final g in available)
            DropdownItem<String>(
              value: g.name,
              intrinsicHeight: true,
              child: AppDropdownItem(
                label: _label(t, g.name),
                leading: GroupDot(colorHex: g.colorHex),
                selected: g.name == group,
              ),
            ),
          DropdownItem<String>(
            value: _newGroupValue,
            intrinsicHeight: true,
            child: AppDropdownItem(
              label: t.groups.newGroup,
              icon: PhosphorIconsRegular.plus,
              color: context.colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

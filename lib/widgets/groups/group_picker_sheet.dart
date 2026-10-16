import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/profile_group.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../ui/app_sheet.dart';
import '../ui/section_header.dart';
import 'group_dot.dart';

/// Asks which group to move the selected records into.
///
/// A sheet rather than the form's dropdown: this is picked once for a batch
/// and then gone, so it has nothing to keep showing afterwards. Returns the
/// group's name, or null when dismissed.
///
/// The group everything already sits in is still listed, just not
/// tappable: a gap where it should be would read as a group having gone
/// missing.
Future<String?> showGroupPickerSheet(
  BuildContext context, {
  required List<ProfileGroup> groups,
  String? current,
}) {
  final t = Translations.of(context);
  return showAppSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space4,
              AppTheme.space20,
              AppTheme.space8,
            ),
            child: SectionHeader(t.selection.moveToGroup),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final group in groups)
                  ListTile(
                    leading: GroupDot(colorHex: group.colorHex, size: 10),
                    title: Text(
                      group.name == GroupStorage.defaultGroup
                          ? t.groups.general
                          : group.name,
                    ),
                    enabled: group.name != current,
                    onTap: () => Navigator.of(ctx).pop(group.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

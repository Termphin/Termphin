import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/settings/sftp_settings.dart';
import '../../theme/theme.dart';
import '../ui/app_sheet.dart';

/// The field and direction the listing is sorted by, or `null` if the sheet
/// was dismissed without a choice.
Future<(SftpSortField, bool)?> showSftpSortSheet(
  BuildContext context, {
  required SftpSortField field,
  required bool descending,
}) {
  final colors = context.colors;
  return showAppSheet<(SftpSortField, bool)>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Text(t.sftp.sortBy, style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(ctx, (field, !descending)),
                  icon: Icon(
                    descending
                        ? PhosphorIconsFill.sortDescending
                        : PhosphorIconsFill.sortAscending,
                    size: 18,
                    color: colors.primary,
                  ),
                  label: Text(t.sftp.sortDirection),
                ),
              ],
            ),
          ),
          RadioGroup<SftpSortField>(
            groupValue: field,
            onChanged: (value) {
              if (value != null) Navigator.pop(ctx, (value, descending));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in SftpSortField.values)
                  RadioListTile<SftpSortField>(
                    value: option,
                    activeColor: colors.primary,
                    title: Text(switch (option) {
                      SftpSortField.name => t.sftp.sortName,
                      SftpSortField.size => t.sftp.sortSize,
                      SftpSortField.modified => t.sftp.sortModified,
                    }, style: TextStyle(color: colors.textPrimary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

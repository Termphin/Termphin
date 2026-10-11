import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../theme/theme.dart';
import '../../utils/sftp_path.dart';

/// Asks how to settle the [conflicts] a copy or move into [folder] found,
/// out of [total] entries being transferred. Null if dismissed without a
/// choice.
Future<ConflictChoice?> askTransferConflict(
  BuildContext context,
  List<String> conflicts, {
  required int total,
  required String folder,
}) {
  final t = Translations.of(context);
  final folderName = sftpPathToDisplay(folder);
  return showDialog<ConflictChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.sftp.conflictTitle),
      content: Text(
        conflicts.length == 1
            ? t.sftp.conflictOne(name: conflicts.single, folder: folderName)
            : t.sftp.conflictMany(
                count: conflicts.length,
                total: total,
                folder: folderName,
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictChoice.skip),
          child: Text(t.sftp.conflictSkip),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictChoice.keepBoth),
          child: Text(t.sftp.conflictKeepBoth),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictChoice.replace),
          child: Text(
            t.sftp.conflictReplace,
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ],
    ),
  );
}

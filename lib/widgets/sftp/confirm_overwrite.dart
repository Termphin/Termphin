import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../ui/confirm_dialog.dart';

/// Asks before an upload replaces [filename] on the server. True to replace
/// it; false to leave it and skip the file.
Future<bool> confirmUploadOverwrite(BuildContext context, String filename) {
  final t = Translations.of(context);
  return showConfirmDialog(
    context,
    title: t.sftp.overwriteTitle,
    message: t.sftp.overwriteConfirm(filename: filename),
    confirmLabel: t.sftp.overwrite,
    destructive: true,
  );
}

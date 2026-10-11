import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';

/// Asks the user to confirm an action: [title], [message], a cancel button
/// and a [confirmLabel] button. True only when the confirm button was
/// pressed; dismissing the dialog counts as cancelling.
///
/// A [destructive] action - deleting, ending, overwriting - draws its
/// confirm button in the palette's error colour, so every dialog that can
/// lose something looks the same.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final t = Translations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel ?? t.common.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: destructive ? TextStyle(color: ctx.colors.error) : null,
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

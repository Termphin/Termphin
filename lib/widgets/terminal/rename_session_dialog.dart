import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/session_tab.dart';
import '../ui/app_notifications.dart';
import '../ui/text_input_dialog.dart';

/// Prompts for a new persistent-session name and validates it locally before
/// handing off to [onRename].
///
/// Sessions this app created (`termphin_*`) only let the user edit the part
/// after the prefix - losing it would make the app unable to tell its own
/// sessions apart from ones the user made by hand. The prefix itself never
/// appears: it is bookkeeping, not part of what the session is called. A
/// foreign session (found through the server-sessions browser, never
/// `termphin_`-prefixed) is never forced into that scheme; it stays freely
/// editable.
Future<void> showRenameSessionDialog(
  BuildContext context, {
  required String currentName,
  required Future<void> Function(String newName) onRename,
}) async {
  final t = Translations.of(context);
  final isOwned = currentName.startsWith(SessionTab.ownedPrefix);
  final editableCurrent = isOwned
      ? currentName.substring(SessionTab.ownedPrefix.length)
      : currentName;

  String buildFullName(String edited) =>
      isOwned ? '${SessionTab.ownedPrefix}$edited' : edited;

  final newSuffix = await showTextInputDialog(
    context,
    title: t.session.renameTitle,
    confirmLabel: t.common.save,
    initialValue: editableCurrent,
    labelText: t.session.renameLabel,
    validator: (value) {
      switch (SessionTab.validateName(buildFullName(value ?? ''))) {
        case 'nameEmpty':
          return t.session.renameNameEmpty;
        case 'nameInvalid':
          return t.session.renameNameInvalid;
        default:
          return null;
      }
    },
  );

  if (newSuffix == null || !context.mounted) return;
  final newName = buildFullName(newSuffix);
  if (newName == currentName) return;

  try {
    await onRename(newName);
    if (context.mounted) {
      AppNotifications.success(context, t.session.renamed(name: newSuffix));
    }
  } catch (error) {
    if (context.mounted) {
      AppNotifications.error(
        context,
        t.session.renameFailed(
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}

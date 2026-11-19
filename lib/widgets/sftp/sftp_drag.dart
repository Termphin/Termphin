import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/sftp/remote_path.dart';
import '../../services/sftp/sftp_remote_ops.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/theme.dart';

/// What a drag out of a file list carries to another list, or to a folder
/// row in any list, on a desktop.
class SftpDragPayload {
  const SftpDragPayload({
    required this.machine,
    required this.sftp,
    required this.sourceDirectory,
    required this.items,
    required this.origin,
    required this.onSourceChanged,
  });

  /// The profile id the source list is connected to. Two lists on the same
  /// machine copy and move on the server; two machines go through the app.
  final String machine;

  /// The source list's channel, which a copy to another machine reads from.
  final SftpService sftp;

  final String sourceDirectory;
  final List<SftpName> items;

  /// The source list itself, so a drop can tell a move within one list from
  /// one between two.
  final Object origin;

  /// Read the source list again: a move took entries out of it.
  final VoidCallback onSourceChanged;

  List<String> get sources => [
    for (final item in items) joinRemotePath(sourceDirectory, item.filename),
  ];
}

/// How a drop lands.
enum SftpDropAction {
  /// A server-side copy on the one machine both lists are on.
  copy,

  /// A server-side move on the one machine both lists are on.
  move,

  /// Down from one machine and up to the other, through the app.
  copyAcross,
}

/// What a drop does, the way a desktop file manager decides it: between two
/// machines always a copy; on one machine a copy into another list unless
/// Shift is held, and a move onto a folder in the same list unless the
/// primary modifier (Ctrl, Cmd on a Mac) is.
SftpDropAction sftpDropAction({
  required bool sameMachine,
  required bool sameList,
  required bool shift,
  required bool primary,
}) {
  if (!sameMachine) return SftpDropAction.copyAcross;
  if (sameList) return primary ? SftpDropAction.copy : SftpDropAction.move;
  return shift ? SftpDropAction.move : SftpDropAction.copy;
}

/// Whether [destination] can take a drop of [payload] from the same machine:
/// not the folder the entries already are in, and not one of the dragged
/// folders or anything inside them.
bool sftpCanDropOnSameMachine(SftpDragPayload payload, String destination) {
  if (sameSftpPath(destination, payload.sourceDirectory)) return false;
  return !payload.sources.any((source) => isSameOrInside(destination, source));
}

/// The chip under the pointer while rows are dragged: the name of the one
/// entry, or how many there are.
class SftpDragFeedback extends StatelessWidget {
  const SftpDragFeedback({super.key, required this.items});

  final List<SftpName> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final single = items.length == 1 ? items.single : null;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space10,
          vertical: AppTheme.space6,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: colors.primary),
          boxShadow: AppTheme.popupShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              single?.attr.isDirectory ?? false
                  ? PhosphorIconsFill.folder
                  : PhosphorIconsFill.files,
              size: AppTheme.icon16,
              color: colors.primary,
            ),
            const SizedBox(width: AppTheme.space6),
            Text(
              single?.filename ?? t.sftp.dragItems(count: items.length),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: AppTheme.font13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

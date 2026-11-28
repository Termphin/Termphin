import 'package:desktop_drop/desktop_drop.dart';

import 'upload_plan.dart';

/// What files dropped on a terminal go up as: each file, read from where the
/// drop left it - a path on disk, or bytes a source handed over without
/// one, which may come without a name too and then goes up as `dropped-N`.
/// Folders are left out and counted, since fast upload sends files.
({List<LocalUpload> uploads, int folders}) droppedUploads(
  Iterable<DropItem> items,
) {
  final uploads = <LocalUpload>[];
  var folders = 0;
  for (final item in items) {
    if (item is DropItemDirectory) {
      folders++;
      continue;
    }
    final name = item.name.isNotEmpty ? item.name : _nameOf(item.path);
    uploads.add(
      LocalUpload(
        name: name.isNotEmpty ? name : 'dropped-${uploads.length + 1}',
        open: item.openRead,
        length: () async {
          try {
            return await item.length();
          } catch (_) {
            return null;
          }
        },
      ),
    );
  }
  return (uploads: uploads, folders: folders);
}

String _nameOf(String path) =>
    path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).lastOrNull ??
    '';

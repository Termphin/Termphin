import 'dart:io';

import '../../models/remote_shell.dart';
import '../ssh/remote_agent_service.dart' show shellQuote, windowsQuote;

/// Where a fast upload's files are going to land, and what gets pasted at the
/// cursor afterwards.
///
/// Split out of `SessionView` because it is arithmetic on strings, and the
/// parts of it that go wrong - two picked files colliding on one remote name,
/// a path with a space in it landing unquoted in a command - are invisible
/// until they have already overwritten something or split an argument in two.

/// A local file on its way to the server: what it is called there, and its
/// bytes - a file on disk, or a stream another app handed over.
class LocalUpload {
  LocalUpload({
    required this.name,
    required Stream<List<int>> Function() open,
    required Future<int?> Function() length,
  }) : _open = open,
       _length = length;

  LocalUpload.file(this.name, String path)
    : _open = (() => File(path).openRead()),
      _length = (() async {
        try {
          return await File(path).length();
        } on FileSystemException {
          return null;
        }
      });

  final String name;
  final Stream<List<int>> Function() _open;
  final Future<int?> Function() _length;

  /// From the first byte on every call, one stream at a time.
  Stream<List<int>> open() => _open();

  /// Null when the source does not say.
  Future<int?> length() => _length();
}

/// A name safe to paste unquoted into a shell: spaces or other punctuation in
/// the original filename would otherwise split into extra arguments the moment
/// it lands in the terminal.
String sanitizedUploadName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return cleaned.length > 120
      ? cleaned.substring(cleaned.length - 120)
      : cleaned;
}

/// Remote paths for one batch of picked files, in the order they were picked.
///
/// [timestamped] is for the scratch directory, where a plain name would
/// collide with the next upload; a directory the user is actually sitting in
/// gets to keep its names.
///
/// Names are made unique *within the batch* either way. A timestamp is not
/// enough on its own: several files picked together are uploaded inside the
/// same millisecond, so two same-named files from different folders would
/// otherwise resolve to one path and the second would quietly overwrite the
/// first. Uniquing is by insertion, so the first file of a name keeps it.
List<String> planUploadPaths({
  required Iterable<String> fileNames,
  required String directory,
  required bool timestamped,
  DateTime? now,
}) {
  final stamp = timestamped
      ? '${(now ?? DateTime.now()).millisecondsSinceEpoch}_'
      : '';
  final base = directory.endsWith('/')
      ? directory.substring(0, directory.length - 1)
      : directory;

  final taken = <String>{};
  return [
    for (final name in fileNames)
      '$base/${_unique('$stamp${sanitizedUploadName(name)}', taken)}',
  ];
}

String _unique(String name, Set<String> taken) {
  if (taken.add(name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  for (var n = 2; ; n++) {
    final candidate = '$stem-$n$extension';
    if (taken.add(candidate)) return candidate;
  }
}

/// What a finished fast upload offers to paste at the cursor.
///
/// Quoted per shell rather than pasted raw: [sanitizedUploadName] only cleans
/// the file's own name, and the directory it landed in is the user's - a
/// Windows temp path under `C:/Users/Jan Kowalski` splits into two arguments
/// the moment it is pasted bare. Several paths are separated by spaces so the
/// whole batch reads as one command's arguments.
String uploadPasteText(Iterable<String> displayPaths, RemoteShellType shell) {
  final quote = shell == RemoteShellType.powershell ? windowsQuote : shellQuote;
  return displayPaths.map(quote).join(' ');
}

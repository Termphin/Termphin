import '../../utils/sftp_path.dart';
import '../ssh/remote_agent_service.dart'
    show powerShellCommandLine, shellQuote;

/// Copy and move between two folders on the same server, done by the server.
///
/// SFTP v3 has no copy, and streaming a tree down to the phone and back up is
/// exactly what this avoids - so a copy is `cp` (or `Copy-Item`) over an exec
/// channel. A move is an SFTP rename first; the command is only its fallback
/// across filesystems, where a rename fails.
///
/// The shell is read off the SFTP path rather than probed: Win32-OpenSSH
/// reports paths as `/C:/...`, and nothing else does.

/// What [execProbeCommand] prints when commands run at all. An account locked
/// to `internal-sftp` runs the SFTP server whatever the command says, and
/// that prints nothing like it.
const execProbeMarker = 'termphin-exec-ok';

bool _isWindows(String path) => isWindowsSftpPath(path);

String _psLiteral(String value) => "'${value.replaceAll("'", "''")}'";

/// Errors go to stderr as one plain line; left uncaught, PowerShell over SSH
/// writes them as CLIXML.
String _powerShell(String body) => powerShellCommandLine(
  "\$ErrorActionPreference = 'Stop'; "
  'try { $body } catch { [Console]::Error.WriteLine(\$_.Exception.Message); '
  'exit 1 }',
);

/// Through `/bin/sh`, so a login shell like fish never gets to reinterpret the
/// quoting.
String _posix(String script) => '/bin/sh -c ${shellQuote(script)}';

String execProbeCommand(String anyPath) => _isWindows(anyPath)
    ? _powerShell('Write-Output $execProbeMarker')
    : _posix('echo $execProbeMarker');

/// `-P` copies a symlink as a link rather than what it points at, `-p` keeps
/// mode and times. POSIX, so BSD, macOS and busybox take it as well.
String copyCommand(String from, String to) => _isWindows(from)
    ? _powerShell(
        'Copy-Item -LiteralPath ${_psLiteral(sftpPathToDisplay(from))} '
        '-Destination ${_psLiteral(sftpPathToDisplay(to))} -Recurse -Force',
      )
    : _posix('cp -RPp -- ${shellQuote(from)} ${shellQuote(to)}');

String moveCommand(String from, String to) => _isWindows(from)
    ? _powerShell(
        'Move-Item -LiteralPath ${_psLiteral(sftpPathToDisplay(from))} '
        '-Destination ${_psLiteral(sftpPathToDisplay(to))} -Force',
      )
    : _posix('mv -- ${shellQuote(from)} ${shellQuote(to)}');

String joinSftpPath(String directory, String name) =>
    directory.endsWith('/') ? '$directory$name' : '$directory/$name';

/// Whether [path] is [ancestor] or somewhere below it. Windows paths compare
/// without case, as the filesystem does.
bool isSameOrInside(String path, String ancestor) {
  var p = path;
  var a = ancestor;
  if (_isWindows(a)) {
    p = p.toLowerCase();
    a = a.toLowerCase();
  }
  if (a.length > 1 && a.endsWith('/')) a = a.substring(0, a.length - 1);
  if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
  if (p == a) return true;
  return p.startsWith(a == '/' ? '/' : '$a/');
}

bool sameSftpPath(String a, String b) =>
    isSameOrInside(a, b) && isSameOrInside(b, a);

final _copySuffix = RegExp(r' \((\d+)\)$');

/// `report (1).pdf`, then `report (2).pdf`. Copying `report (1).pdf` again
/// gives `report (2).pdf`, not `report (1) (1).pdf`.
/// [taken] holds names as [key] maps them. A leading dot is taken to be part
/// of the name, not an extension.
String nextFreeName(
  String name,
  Set<String> taken, {
  required bool isDirectory,
  String Function(String name)? key,
}) {
  var stem = name;
  var extension = '';
  if (!isDirectory) {
    final lower = name.toLowerCase();
    final tar = RegExp(r'\.tar\.[a-z0-9]+$').firstMatch(lower);
    final dot = tar?.start ?? name.lastIndexOf('.');
    if (dot > 0) {
      stem = name.substring(0, dot);
      extension = name.substring(dot);
    }
  }
  stem = stem.replaceFirst(_copySuffix, '');
  for (var n = 1; ; n++) {
    final candidate = '$stem ($n)$extension';
    if (!taken.contains(key?.call(candidate) ?? candidate)) return candidate;
  }
}

enum ConflictChoice { skip, replace, keepBoth }

class RemoteEntry {
  const RemoteEntry(this.name, {required this.isDirectory});

  final String name;
  final bool isDirectory;
}

class PlannedTransfer {
  const PlannedTransfer({
    required this.entry,
    required this.from,
    required this.to,
    required this.replaceExisting,
  });

  final RemoteEntry entry;
  final String from;
  final String to;

  /// The destination holds something by this name and it goes first.
  final bool replaceExisting;
}

class TransferPlan {
  const TransferPlan(this.transfers, this.skipped);

  final List<PlannedTransfer> transfers;
  final int skipped;
}

/// How a name is compared in [folder]: Windows ignores case, so `A.txt` would
/// land on `a.txt` - and `Copy-Item -Force` would overwrite it unasked.
String Function(String) _nameKey(String folder) =>
    _isWindows(folder) ? (name) => name.toLowerCase() : (name) => name;

/// Names in [entries] already taken in [destination].
List<String> transferConflicts(
  List<RemoteEntry> entries,
  Set<String> existing, {
  required String destination,
}) {
  final key = _nameKey(destination);
  final taken = {for (final name in existing) key(name)};
  return [
    for (final e in entries)
      if (taken.contains(key(e.name))) e.name,
  ];
}

/// [existing] is the destination's listing. Keeping both picks names that
/// clash neither with it nor with each other. Replacing skips an entry
/// instead when clearing its destination name would delete the source -
/// a folder the source itself sits inside.
TransferPlan planTransfers({
  required String sourceDirectory,
  required List<RemoteEntry> entries,
  required String destination,
  required Set<String> existing,
  required ConflictChoice choice,
}) {
  final key = _nameKey(destination);
  final present = {for (final name in existing) key(name)};
  final taken = {...present};
  final transfers = <PlannedTransfer>[];
  var skipped = 0;
  for (final entry in entries) {
    final from = joinSftpPath(sourceDirectory, entry.name);
    var name = entry.name;
    var replace = false;
    if (taken.contains(key(name))) {
      switch (choice) {
        case ConflictChoice.skip:
          skipped++;
          continue;
        case ConflictChoice.keepBoth:
          name = nextFreeName(
            name,
            taken,
            isDirectory: entry.isDirectory,
            key: key,
          );
        case ConflictChoice.replace:
          if (isSameOrInside(from, joinSftpPath(destination, name))) {
            skipped++;
            continue;
          }
          replace = present.contains(key(name));
      }
    }
    taken.add(key(name));
    transfers.add(
      PlannedTransfer(
        entry: entry,
        from: from,
        to: joinSftpPath(destination, name),
        replaceExisting: replace,
      ),
    );
  }
  return TransferPlan(transfers, skipped);
}

/// Whether [destination] can take [sources] (full paths). A folder cannot go
/// into itself or below itself, and a move into the folder it is already in
/// changes nothing.
bool canTransferInto({
  required String destination,
  required String sourceDirectory,
  required List<String> sources,
  required bool move,
}) {
  if (move && sameSftpPath(destination, sourceDirectory)) return false;
  return !sources.any((s) => isSameOrInside(destination, s));
}

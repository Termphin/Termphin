/// The SFTP protocol reports Windows paths as `/C:/Users/...` - POSIX-style,
/// drive letter as the first segment - never bare `C:/Users/...`. Every path
/// shown to the user (path bar, breadcrumbs, copy-path) is converted to
/// `C:\Users\...` for display; every path sent back over SFTP is converted
/// the other way first. Internal navigation state always stays in the
/// POSIX/SFTP form - only display and copy touch these.
/// Trailing slash optional: going up from `/C:/Users` lands on `/C:`.
final _driveLetterRe = RegExp(r'^/[A-Za-z]:(?:/|$)');

bool isWindowsSftpPath(String path) => _driveLetterRe.hasMatch(path);

/// Bare `C:` means the current directory on that drive, not its root, so a
/// trailing separator is added back for that case alone.
String sftpPathToDisplay(String posixPath) {
  if (!_driveLetterRe.hasMatch(posixPath)) return posixPath;
  final native = posixPath.substring(1).replaceAll('/', r'\');
  return native.length == 2 ? '$native\\' : native;
}

/// Accepts every shape a Windows path arrives in - typed into the path bar,
/// pasted from Explorer, or handed back from [sftpPathToDisplay]: `C:`,
/// `C:\`, `C:\Users`, and the forward-slash spellings Windows also takes.
/// A bare drive root (`C:\`) keeps its trailing separator, which is stripped
/// here so joining a filename onto it doesn't produce a double slash.
String displayPathToSftp(String value) {
  if (!RegExp(r'^[A-Za-z]:([\\/]|$)').hasMatch(value)) return value;
  final posix = value.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
  return '/$posix';
}

/// One level up, stopping at `/` or a drive root (`/C:/`).
String sftpParentPath(String path) {
  final isWindows = isWindowsSftpPath(path);
  final parts = path.split('/')..removeWhere((p) => p.isEmpty);
  if (parts.isNotEmpty) parts.removeLast();
  if (isWindows) {
    if (parts.length <= 1) return '/${path.substring(1, 3)}/';
    return '/${parts.join('/')}';
  }
  return '/${parts.join('/')}';
}

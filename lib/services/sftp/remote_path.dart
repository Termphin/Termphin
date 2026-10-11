import '../../utils/sftp_path.dart';

/// The breadcrumb segments of [path]: a drive letter followed by its
/// sub-folders on a Windows path (`/C:/Users/me` → `['C:', 'Users', 'me']`),
/// every non-empty component elsewhere.
List<String> remotePathSegments(String path) {
  if (isWindowsSftpPath(path)) {
    final drive = path.substring(1, 3);
    final rest = path.substring(4);
    final parts = rest.split('/').where((p) => p.isNotEmpty).toList();
    return [drive, ...parts];
  }
  return path.split('/').where((p) => p.isNotEmpty).toList();
}

/// [directory] with [name] appended as a child entry.
String joinRemotePath(String directory, String name) {
  if (directory.endsWith('/')) return '$directory$name';
  return '$directory/$name';
}

/// Where tapping the breadcrumb at [index] in [path] goes.
String remoteSegmentPath(String path, int index) {
  final segments = remotePathSegments(path);
  if (isWindowsSftpPath(path)) {
    if (index == 0) return '/${segments[0]}/';
    return '/${segments[0]}/${segments.sublist(1, index + 1).join('/')}';
  }
  return '/${segments.sublist(0, index + 1).join('/')}';
}

/// Where the root breadcrumb in [path] goes: the drive root on a Windows
/// path, `/` elsewhere.
String remoteRootPath(String path) =>
    isWindowsSftpPath(path) ? '/${remotePathSegments(path)[0]}/' : '/';

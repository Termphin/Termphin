import '../i18n/strings.g.dart';

String resolveSftpError(Object error, Translations t) {
  final msg = error.toString().replaceFirst('Exception: ', '');
  if (msg.startsWith('sftp.errors.')) {
    final key = msg.substring('sftp.errors.'.length);
    return switch (key) {
      'notFound' => t.sftp.errors.notFound,
      'permissionDenied' => t.sftp.errors.permissionDenied,
      'failure' => t.sftp.errors.failure,
      'connectionLost' => t.sftp.errors.connectionLost,
      'diskFull' => t.sftp.errors.diskFull,
      'fileLocked' => t.sftp.errors.fileLocked,
      'networkError' => t.sftp.errors.networkError,
      'timeout' => t.sftp.errors.timeout,
      'localWriteError' => t.sftp.errors.localWriteError,
      'uploadReadError' => t.sftp.errors.uploadReadError,
      'cancelled' => t.sftp.errors.cancelled,
      'noShell' => t.sftp.errors.noShell,
      _ => t.sftp.errors.generic(error: msg),
    };
  }
  return t.sftp.errors.generic(error: msg);
}

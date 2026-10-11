import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/utils/sftp_error_handler.dart';

void main() {
  final t = AppLocale.en.buildSync();

  test('maps known sftp error keys to translated messages', () {
    expect(
      resolveSftpError(Exception('sftp.errors.notFound'), t),
      t.sftp.errors.notFound,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.permissionDenied'), t),
      t.sftp.errors.permissionDenied,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.connectionLost'), t),
      t.sftp.errors.connectionLost,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.diskFull'), t),
      t.sftp.errors.diskFull,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.fileLocked'), t),
      t.sftp.errors.fileLocked,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.networkError'), t),
      t.sftp.errors.networkError,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.timeout'), t),
      t.sftp.errors.timeout,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.localWriteError'), t),
      t.sftp.errors.localWriteError,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.uploadReadError'), t),
      t.sftp.errors.uploadReadError,
    );
    expect(
      resolveSftpError(Exception('sftp.errors.cancelled'), t),
      t.sftp.errors.cancelled,
    );
  });

  test('unknown sftp error key falls back to the generic message', () {
    expect(
      resolveSftpError(Exception('sftp.errors.surprise'), t),
      t.sftp.errors.generic(error: 'sftp.errors.surprise'),
    );
  });

  test('the Exception: prefix is stripped before mapping', () {
    final raw = Exception('sftp.errors.failure');
    expect(raw.toString(), startsWith('Exception: '));
    expect(resolveSftpError(raw, t), t.sftp.errors.failure);
  });

  test('arbitrary errors render through the generic message', () {
    expect(resolveSftpError('boom', t), t.sftp.errors.generic(error: 'boom'));
  });
}

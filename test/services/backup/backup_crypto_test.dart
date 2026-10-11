import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/backup/backup_crypto.dart';

void main() {
  const secret = 'correct horse battery staple';

  test('a sealed backup keeps its header readable', () async {
    final sealed = await encryptBackup('{"profiles":[]}', secret);
    final envelope = jsonDecode(sealed) as Map<String, dynamic>;

    expect(envelope['format'], kBackupFormat);
    expect(envelope['version'], kBackupVersion);
    expect(envelope['encrypted'], isTrue);
    expect(isEncryptedBackup(sealed), isTrue);
    expect(isEncryptedBackup('{"profiles":[]}'), isFalse);
  });

  test('round trips through the right passphrase only', () async {
    final sealed = await encryptBackup('{"profiles":[1,2,3]}', secret);

    expect(await decryptBackup(sealed, secret), '{"profiles":[1,2,3]}');
    await expectLater(
      decryptBackup(sealed, 'wrong horse'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.wrongPassphrase,
        ),
      ),
    );
  });

  test('two exports of the same data do not share ciphertext', () async {
    final first = jsonDecode(await encryptBackup('{}', secret)) as Map;
    final second = jsonDecode(await encryptBackup('{}', secret)) as Map;

    expect(
      (first['kdf'] as Map)['salt'],
      isNot((second['kdf'] as Map)['salt']),
    );
    expect(first['payload'], isNot(second['payload']));
  });

  test('an edited payload fails to open rather than opening short', () async {
    final sealed = jsonDecode(await encryptBackup('{"a":1}', secret)) as Map;
    final payload = sealed['payload'] as String;
    final tampered = jsonEncode({
      ...sealed,
      'payload': payload.replaceRange(payload.length - 2, null, 'AA'),
    });

    await expectLater(
      decryptBackup(tampered, secret),
      throwsA(isA<BackupFormatException>()),
    );
  });
}

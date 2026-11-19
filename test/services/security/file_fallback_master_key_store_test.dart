import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/security/file_fallback_master_key_store.dart';

import '../../support/fake_master_key_store.dart';

/// A keyring that is not there: the Secret Service of a session started
/// without one answers every call with an error.
class _NoKeyring extends FakeMasterKeyStore {
  @override
  Future<String?> read() async => throw Exception('not activatable');

  @override
  Future<void> write(String value) async => throw Exception('not activatable');
}

void main() {
  late Directory dir;
  late File keyFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('termphin-key');
    keyFile = File('${dir.path}/support/master_key');
    FileFallbackMasterKeyStore.usingFile.value = false;
  });

  tearDown(() => dir.delete(recursive: true));

  FileFallbackMasterKeyStore store(FakeMasterKeyStore primary) =>
      FileFallbackMasterKeyStore(
        primary: primary,
        keyFile: () async => keyFile,
      );

  test('with no keyring the key goes to a file only its owner can read, '
      'and Settings is told', () async {
    final s = store(_NoKeyring());

    expect(await s.read(), isNull);
    await s.write('the-key');

    expect(FileFallbackMasterKeyStore.usingFile.value, isTrue);
    expect(await keyFile.readAsString(), 'the-key');
    final mode = (await keyFile.stat()).mode & 0x1ff;
    expect(mode.toRadixString(8), '600');

    expect(await store(_NoKeyring()).read(), 'the-key');
  }, testOn: 'linux || mac-os');

  test('a keyring that answers is used and no file is written', () async {
    final keyring = FakeMasterKeyStore();
    final s = store(keyring);

    expect(await s.read(), isNull);
    await s.write('the-key');

    expect(keyring.value, 'the-key');
    expect(await keyFile.exists(), isFalse);
    expect(FileFallbackMasterKeyStore.usingFile.value, isFalse);
  });

  test(
    'a key left in the file moves into a keyring that appears later',
    () async {
      await store(_NoKeyring()).write('the-key');
      final keyring = FakeMasterKeyStore();

      expect(await store(keyring).read(), 'the-key');

      expect(keyring.value, 'the-key');
      expect(await keyFile.exists(), isFalse);
      expect(FileFallbackMasterKeyStore.usingFile.value, isFalse);
    },
    testOn: 'linux || mac-os',
  );

  test('a keyring that already holds a key wins over a stray file', () async {
    await store(_NoKeyring()).write('from-file');
    final keyring = FakeMasterKeyStore('from-keyring');

    expect(await store(keyring).read(), 'from-keyring');
    expect(await keyFile.exists(), isTrue);
  }, testOn: 'linux || mac-os');
}

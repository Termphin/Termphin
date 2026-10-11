import 'dart:math';

import 'package:termphin/services/security/secret_cipher.dart';

/// In-memory stand-in for the Android Keystore, so storage tests do not need a
/// platform channel.
class FakeMasterKeyStore implements MasterKeyStore {
  FakeMasterKeyStore([this.value]);

  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    value = next;
    writes++;
  }
}

SecretCipher cipherFixture({MasterKeyStore? store, int seed = 1}) =>
    SecretCipher(store: store ?? FakeMasterKeyStore(), random: Random(seed));

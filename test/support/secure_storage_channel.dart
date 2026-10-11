import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Backs `flutter_secure_storage` with an in-memory map for tests that reach
/// `SecretCipher.instance` through production code rather than injecting a
/// cipher of their own.
///
/// Call from `setUp`. The store is per-call, so each test starts with a fresh
/// master key - which also means values sealed in one test cannot be opened in
/// the next.
void mockSecureStorage() {
  final entries = <String, String>{};
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        final arguments = (call.arguments as Map?)?.cast<String, Object?>();
        final key = arguments?['key'] as String?;
        return switch (call.method) {
          'read' => entries[key],
          'write' => entries[key!] = arguments!['value'] as String,
          'delete' => entries.remove(key),
          'readAll' => Map<String, String>.from(entries),
          'deleteAll' => entries.clear(),
          'containsKey' => entries.containsKey(key),
          _ => null,
        };
      });
}

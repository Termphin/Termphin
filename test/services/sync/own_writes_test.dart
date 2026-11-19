import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/sync/sync_service.dart';

void main() {
  final written = {
    'profile-1': writtenAs({'ciphertext': 'sealed-a', 'deleted': false}),
    'profile-2': writtenAs({'ciphertext': '', 'deleted': true}),
  };

  test('the server confirming this device own write starts no sync', () {
    expect(
      ownWritesOnly([
        (
          'profile-1',
          {'ciphertext': 'sealed-a', 'deleted': false, 'updatedAt': 1},
        ),
        ('profile-2', {'ciphertext': '', 'deleted': true, 'updatedAt': 2}),
      ], written),
      isTrue,
    );
  });

  test('another device writing the same record does', () {
    expect(
      ownWritesOnly([
        ('profile-1', {'ciphertext': 'sealed-b', 'deleted': false}),
      ], written),
      isFalse,
    );
  });

  test('a record this device never wrote does', () {
    expect(
      ownWritesOnly([
        ('profile-9', {'ciphertext': 'sealed-x', 'deleted': false}),
      ], written),
      isFalse,
    );
  });

  test('a record removed outright does', () {
    expect(ownWritesOnly([('profile-1', null)], written), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/models/ssh_profile.dart';
import 'package:termphin/services/ssh/ssh_service.dart';
import 'package:termphin/utils/connection_error_text.dart';

void main() {
  final t = AppLocale.en.buildSync();

  String textFor(
    SshFailureReason? reason, {
    AuthMethod authMethod = AuthMethod.password,
    String fallback = 'raw driver text',
  }) => connectionErrorText(t, reason, authMethod, fallback: fallback);

  test('a rejected credential reads differently for a key than a password', () {
    expect(
      textFor(SshFailureReason.authFailed, authMethod: AuthMethod.password),
      t.connection.errors.authFailedPassword,
    );
    expect(
      textFor(SshFailureReason.authFailed, authMethod: AuthMethod.privateKey),
      t.connection.errors.authFailedKey,
    );
  });

  test('a key problem names the key, not the credentials', () {
    expect(
      textFor(SshFailureReason.keyPassphrase),
      t.connection.errors.keyPassphrase,
    );
    expect(
      textFor(SshFailureReason.keyInvalid),
      t.connection.errors.keyInvalid,
    );
    expect(
      textFor(SshFailureReason.keyMissing),
      t.connection.errors.keyMissing,
    );
  });

  test('reasons carrying driver text fall back to the thrown message', () {
    for (final reason in [
      SshFailureReason.authError,
      SshFailureReason.protocol,
      SshFailureReason.unknown,
      null,
    ]) {
      expect(textFor(reason), 'raw driver text', reason: '$reason');
    }
  });

  test('every other reason is translated rather than shown raw', () {
    const raw = 'raw driver text';
    const fallsBack = {
      SshFailureReason.authError,
      SshFailureReason.protocol,
      SshFailureReason.unknown,
    };

    for (final reason in SshFailureReason.values) {
      if (fallsBack.contains(reason)) continue;
      expect(
        textFor(reason),
        isNot(raw),
        reason: '$reason has no string in connection.errors',
      );
    }
  });
}

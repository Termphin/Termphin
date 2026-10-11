import '../i18n/strings.g.dart';
import '../models/ssh_profile.dart';
import '../services/app/manual_urls.dart';
import '../services/ssh/ssh_service.dart';

/// What to put on screen for a failed connection.
///
/// [SshFailureReason] is the classification made where the failure was thrown;
/// [fallback] is the message thrown with it, which is written in English and
/// interpolates addresses and driver text. Reasons that say something the user
/// can act on are translated here, and the rest fall back - a protocol
/// mismatch or an unclassified error is worth showing verbatim, since the
/// driver's own words are all anyone has to go on.
///
/// A rejected credential reads differently depending on what was offered, so
/// [authMethod] picks between the two.
String connectionErrorText(
  Translations t,
  SshFailureReason? reason,
  AuthMethod authMethod, {
  required String fallback,
}) {
  final e = t.connection.errors;
  return switch (reason) {
    SshFailureReason.hostUnreachable => e.hostUnreachable,
    SshFailureReason.localNetworkBlocked => e.localNetworkBlocked,
    SshFailureReason.localNetworkUnverified => e.localNetworkUnverified,
    SshFailureReason.timeout => e.timeout,
    SshFailureReason.authFailed =>
      authMethod == AuthMethod.privateKey
          ? e.authFailedKey
          : e.authFailedPassword,
    SshFailureReason.hostKeyRejected => e.hostKeyRejected,
    SshFailureReason.hostKeyMismatch => e.hostKeyMismatch,
    SshFailureReason.keyMissing => e.keyMissing,
    SshFailureReason.keyPassphrase => e.keyPassphrase,
    SshFailureReason.keyInvalid => e.keyInvalid,
    SshFailureReason.jumpHost => e.jumpHost,
    SshFailureReason.jumpHostConfig => e.jumpHostConfig,
    SshFailureReason.authError ||
    SshFailureReason.protocol ||
    SshFailureReason.unknown ||
    null => fallback,
  };
}

/// Where the manual explains the failure [connectionErrorText] describes.
///
/// The troubleshooting page has a heading per message, so each reason lands on
/// its own; what has no heading lands on the top, which starts from the
/// connection log.
ManualPage connectionErrorManualPage(
  SshFailureReason? reason,
  AuthMethod authMethod,
) {
  return switch (reason) {
    SshFailureReason.hostUnreachable ||
    SshFailureReason.timeout => ManualPage.hostUnreachable,
    SshFailureReason.localNetworkBlocked => ManualPage.localNetworkBlocked,
    SshFailureReason.localNetworkUnverified =>
      ManualPage.localNetworkUnverified,
    SshFailureReason.authFailed || SshFailureReason.authError =>
      authMethod == AuthMethod.privateKey
          ? ManualPage.keyRefused
          : ManualPage.wrongPassword,
    SshFailureReason.hostKeyRejected => ManualPage.hostKeyRejected,
    SshFailureReason.hostKeyMismatch => ManualPage.hostKeyChanged,
    SshFailureReason.keyMissing ||
    SshFailureReason.keyPassphrase ||
    SshFailureReason.keyInvalid => ManualPage.keyUnreadable,
    SshFailureReason.jumpHost ||
    SshFailureReason.jumpHostConfig => ManualPage.jumpHost,
    SshFailureReason.protocol ||
    SshFailureReason.unknown ||
    null => ManualPage.troubleshooting,
  };
}

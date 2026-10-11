import '../../models/known_host.dart';
import '../storage/write_queue.dart';

/// The questions a connection can only answer by asking the person holding
/// the phone. Declared away from both the SSH layer that raises them and the
/// widgets that answer them, so neither has to import the other.

class HostKeyPromptRequest {
  const HostKeyPromptRequest({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.verdict,
    this.pinnedFingerprint,
  });

  final String host;
  final int port;
  final String keyType;

  /// What the server just presented, `SHA256:<base64>`.
  final String fingerprint;

  /// [HostKeyVerdict.unknown] for first contact, [HostKeyVerdict.changed] when
  /// this address is already pinned to something else. Never
  /// [HostKeyVerdict.trusted] - that case never reaches a prompt.
  final HostKeyVerdict verdict;

  /// What was pinned before, set only when [verdict] is
  /// [HostKeyVerdict.changed].
  final String? pinnedFingerprint;
}

/// Returns true to accept and pin the key, false to abort the connection.
typedef HostKeyPrompt = Future<bool> Function(HostKeyPromptRequest request);

class KeyboardInteractiveQuestion {
  const KeyboardInteractiveQuestion({required this.prompt, required this.echo});

  final String prompt;

  /// False for anything secret - the server asking for a password or a TOTP
  /// code says so here, and the field is obscured on our side because of it.
  final bool echo;
}

class KeyboardInteractiveRequest {
  const KeyboardInteractiveRequest({
    required this.name,
    required this.instruction,
    required this.questions,
  });

  /// Server-supplied heading, e.g. "Password Expired". Often empty.
  final String name;

  /// Server-supplied explanation. Often empty.
  final String instruction;

  final List<KeyboardInteractiveQuestion> questions;
}

/// One answer per question, in order. Null cancels the attempt.
typedef KeyboardInteractivePrompt =
    Future<List<String>?> Function(KeyboardInteractiveRequest request);

/// Holds every connection's questions to one at a time.
///
/// Several handshakes can be in flight at once - a group loading the sessions
/// of all its machines, two tabs dialling together - and each can raise a
/// dialog about a different host. Stacked, the one underneath is answered
/// blind, and a host key is exactly the question that must not be. The wait
/// costs the connection nothing: `SshService` hands time spent in a prompt
/// back to the auth timeout, and that accounting starts when the callback is
/// invoked, so the queueing happens inside it.
class ConnectionPromptQueue {
  final WriteQueue _queue = WriteQueue();

  HostKeyPrompt hostKey(HostKeyPrompt prompt) =>
      (request) => _queue.run(() => prompt(request));

  KeyboardInteractivePrompt keyboardInteractive(
    KeyboardInteractivePrompt prompt,
  ) =>
      (request) => _queue.run(() => prompt(request));
}

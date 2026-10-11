import 'dart:async';

/// Thrown when a transfer is stopped by the user. The message doubles as the
/// translation key the rest of the SFTP layer speaks in, so `resolveSftpError`
/// keeps working without knowing this type exists.
class TransferCancelled implements Exception {
  const TransferCancelled();

  @override
  String toString() => 'Exception: sftp.errors.cancelled';
}

/// Cancellation for one transfer.
///
/// [isCancelled] is what a loop polls between chunks; [whenCancelled] is what
/// lets a *stalled* read give up the moment the user asks, instead of waiting
/// for a next chunk that may never arrive.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const TransferCancelled();
  }

  /// Fails [operation] as soon as the token trips, for awaits that have no
  /// cancellation of their own. The operation itself keeps running; the caller
  /// is expected to tear down whatever it was writing to.
  Future<T> race<T>(Future<T> operation) {
    if (isCancelled) throw const TransferCancelled();
    return Future.any([
      operation,
      whenCancelled.then<T>((_) => throw const TransferCancelled()),
    ]);
  }
}

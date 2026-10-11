import 'dart:async';

/// Runs the actions handed to it one after another, never two at once.
///
/// Every storage class here mutates by loading the whole list, changing one
/// entry and writing the list back. Two of those cycles overlapping means the
/// second one reads the state from before the first one's write, and its own
/// write then silently erases it. Funnelling the mutations through one of
/// these makes that impossible without any of them needing to know about the
/// others.
class WriteQueue {
  Future<void> _tail = Future<void>.value();

  /// Runs [action] once every action queued before it has finished.
  ///
  /// The chain must stay unbroken whatever [action] does: an error escaping
  /// here would leave `_tail` completed with it and reject every later
  /// caller. It is forwarded to this call's own future instead.
  Future<T> run<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

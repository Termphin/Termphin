import 'package:flutter/services.dart';

import '../../utils/platform_info.dart';

/// The few seconds of execution iOS grants an app on its way out.
///
/// `UIApplication.beginBackgroundTask` is not a foreground service and cannot
/// stand in for one: the system grants around thirty seconds and then suspends
/// the process anyway, so it holds no SSH session open. What it is enough for
/// is letting a transfer already in flight finish writing instead of being cut
/// off mid-file, which is why only [SftpService]'s callers reach for it.
///
/// Android needs none of this - its foreground service already holds the
/// process - so every call is a no-op there.
class IOSBackgroundTask {
  IOSBackgroundTask._();

  static const _channel = MethodChannel(
    'dev.termphin.termphin/background_task',
  );

  /// Runs [action] with the grant held, and gives it back afterwards however
  /// [action] ended. Holding one past its expiry is what makes iOS kill the
  /// app rather than suspend it.
  static Future<T> guard<T>(String name, Future<T> Function() action) async {
    if (!isIOSPlatform) return action();
    final token = await _begin(name);
    try {
      return await action();
    } finally {
      if (token != null) await _end(token);
    }
  }

  static Future<int?> _begin(String name) async {
    try {
      return await _channel.invokeMethod<int>('begin', {'name': name});
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Ends the grant for [token]. A [PlatformException] means it already
  /// expired, with nothing left to give back; a [MissingPluginException]
  /// means nothing registered this channel, so nothing was begun either.
  static Future<void> _end(int token) async {
    try {
      await _channel.invokeMethod('end', {'token': token});
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}

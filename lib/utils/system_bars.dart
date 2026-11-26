import 'package:flutter/services.dart';

import 'platform_info.dart';

/// Lets Termphin draw under the status and navigation bars on every Android
/// version, as Android 15 and later require anyway. Without it, Android 14
/// and older with three-button navigation hand Flutter the navigation bar's
/// height as bottom padding while the app already ends above that bar, so
/// every bottom inset - the floating navigation bar first of all - was
/// counted twice and left a band of empty screen under it.
Future<void> drawBehindSystemBars() async {
  if (!isAndroidPlatform) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

import '../../utils/platform_info.dart';

/// Where the Mac build looks for new versions: the appcast published with
/// every release, next to its signed DMG. A build made to test updates
/// points elsewhere at build time.
const kAppcastUrl = String.fromEnvironment(
  'SPARKLE_FEED_URL',
  defaultValue:
      'https://github.com/Termphin/Termphin/releases/latest/download/appcast.xml',
);

/// Updates for the desktop build outside a store: Sparkle on macOS, which
/// reads the appcast, checks each update's EdDSA signature against the key
/// in Info.plist (`SUPublicEDKey`), and asks before installing. It looks
/// once at launch, quietly, and then once a day; Help in the menus asks at
/// once.
class AppUpdater {
  AppUpdater._();

  static final instance = AppUpdater._();

  /// Whether this build updates itself: only the Mac one so far.
  bool get supported => platformHas(PlatformFeature.selfUpdates);

  bool _started = false;

  /// Points Sparkle at the appcast and has it check quietly now and daily.
  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    try {
      await autoUpdater.setFeedURL(kAppcastUrl);
      await autoUpdater.setScheduledCheckInterval(86400);
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (error) {
      debugPrint('Updates could not start: $error');
    }
  }

  /// Checks now, with Sparkle's own window saying what it found.
  Future<void> checkNow() async {
    if (!supported) return;
    await start();
    try {
      await autoUpdater.checkForUpdates();
    } catch (error) {
      debugPrint('Could not check for updates: $error');
    }
  }
}

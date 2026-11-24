import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import 'appcast_parser.dart';
import 'linux_self_updater.dart';

/// Where the Mac build looks for new versions: the appcast published with
/// every release, next to its signed DMG. A build made to test updates
/// points elsewhere at build time.
const kAppcastUrl = String.fromEnvironment(
  'SPARKLE_FEED_URL',
  defaultValue:
      'https://github.com/Termphin/Termphin/releases/latest/download/appcast.xml',
);

/// Updates for desktop builds outside a store: Sparkle on macOS and signed
/// self-replacing AppImage updates on Linux. Both verify an Ed25519 signature
/// before installing anything.
class AppUpdater {
  AppUpdater._();

  static final instance = AppUpdater._();

  /// Whether this build updates itself: macOS, or Linux running as an AppImage.
  bool get supported => platformHas(PlatformFeature.selfUpdates);

  bool _started = false;
  bool _busy = false;
  BuildContext? Function()? _contextProvider;

  /// Supplies the navigator context so background update checks on Linux can
  /// raise an in-app toast once the UI has mounted.
  void bindContext(BuildContext? Function() contextProvider) {
    _contextProvider = contextProvider;
  }

  /// Starts quiet update checking at launch.
  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    if (isMacOSPlatform) {
      await _startMacOS();
      return;
    }
    if (isLinuxPlatform) {
      unawaited(_checkLinuxQuietly());
    }
  }

  /// Checks now and surfaces the result to the user.
  Future<void> checkNow({BuildContext? context}) async {
    if (!supported) return;
    if (isMacOSPlatform) {
      await start();
      try {
        await autoUpdater.checkForUpdates();
      } catch (error) {
        debugPrint('Could not check for updates: $error');
      }
      return;
    }
    if (isLinuxPlatform) {
      await _checkLinuxNow(context ?? _contextProvider?.call());
    }
  }

  Future<void> _startMacOS() async {
    try {
      await autoUpdater.setFeedURL(kAppcastUrl);
      await autoUpdater.setScheduledCheckInterval(86400);
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (error) {
      debugPrint('Updates could not start: $error');
    }
  }

  LinuxSelfUpdater? _createLinuxUpdater() {
    final path = currentAppImagePath;
    if (path == null) return null;
    return LinuxSelfUpdater(appImagePath: path);
  }

  Future<void> _checkLinuxQuietly() async {
    final updater = _createLinuxUpdater();
    if (updater == null || _busy) return;
    try {
      final entry = await updater.checkForUpdate();
      if (entry == null) return;
      final ctx = await _waitForContext();
      if (ctx == null || !ctx.mounted) return;
      final t = Translations.of(ctx);
      AppNotifications.show(
        ctx,
        t.updates.availableNotice(version: entry.version),
        kind: AppNotificationKind.info,
        actionLabel: t.updates.install,
        onAction: () {
          final currentCtx = _contextProvider?.call();
          if (currentCtx != null && currentCtx.mounted) {
            unawaited(_promptAndInstall(currentCtx, updater, entry));
          }
        },
      );
    } catch (error) {
      debugPrint('Background update check failed: $error');
    }
  }

  Future<BuildContext?> _waitForContext() async {
    for (var i = 0; i < 20; i++) {
      final ctx = _contextProvider?.call();
      if (ctx != null && ctx.mounted) return ctx;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<void> _checkLinuxNow(BuildContext? ctx) async {
    final updater = _createLinuxUpdater();
    if (updater == null || _busy) return;
    _busy = true;
    AppcastEntry? entry;
    try {
      entry = await updater.checkForUpdate();
    } catch (error) {
      debugPrint('Could not check for updates: $error');
      _busy = false;
      if (ctx != null && ctx.mounted) {
        AppNotifications.error(ctx, Translations.of(ctx).updates.checkFailed);
      }
      return;
    }

    if (entry == null) {
      _busy = false;
      if (ctx != null && ctx.mounted) {
        AppNotifications.info(ctx, Translations.of(ctx).updates.upToDate);
      }
      return;
    }

    _busy = false;
    if (ctx != null && ctx.mounted) {
      await _promptAndInstall(ctx, updater, entry);
    }
  }

  Future<void> _promptAndInstall(
    BuildContext ctx,
    LinuxSelfUpdater updater,
    AppcastEntry entry,
  ) async {
    if (_busy) return;
    final t = Translations.of(ctx);
    final confirmed = await showConfirmDialog(
      ctx,
      title: t.updates.availableTitle,
      message: t.updates.availableMessage(
        version: entry.version,
        build: entry.buildNumber,
      ),
      confirmLabel: t.updates.install,
    );
    if (!confirmed || !ctx.mounted) return;

    _busy = true;
    AppNotifications.info(
      ctx,
      t.updates.downloading(version: entry.version),
    );
    try {
      await updater.downloadAndInstall(entry);
    } catch (error) {
      debugPrint('Update install failed: $error');
      _busy = false;
      if (ctx.mounted) {
        AppNotifications.error(ctx, t.updates.installFailed);
      }
      return;
    }
    _busy = false;

    if (!ctx.mounted) return;
    final restart = await showConfirmDialog(
      ctx,
      title: t.updates.readyTitle,
      message: t.updates.readyMessage(version: entry.version),
      confirmLabel: t.updates.restartNow,
      cancelLabel: t.updates.later,
    );
    if (restart) {
      await updater.restartApp();
    }
  }
}

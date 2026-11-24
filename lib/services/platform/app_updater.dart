import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/confirm_dialog.dart';
import '../../widgets/window/update_download_dialog.dart';
import 'appcast_fetcher.dart';
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
///
/// Background checks at launch and every [kCheckInterval] stay completely
/// silent on both platforms — surfacing only a subtle indicator in the bottom
/// status bar until the user chooses to update.
class AppUpdater {
  AppUpdater._();

  static final instance = AppUpdater._();

  /// Whether this build updates itself: macOS, or Linux running as an AppImage.
  bool get supported => platformHas(PlatformFeature.selfUpdates);

  /// Interval between background update checks on desktop.
  static const kCheckInterval = Duration(hours: 24);

  bool _started = false;
  bool _macConfigured = false;
  bool _busy = false;
  Timer? _checkTimer;
  BuildContext? Function()? _contextProvider;

  /// Latest update discovered by a background or manual check, observed by
  /// the desktop status bar.
  final availableUpdate = ValueNotifier<AppcastEntry?>(null);

  /// Supplies the navigator context so status-bar update actions can open
  /// dialogs cleanly.
  void bindContext(BuildContext? Function() contextProvider) {
    _contextProvider = contextProvider;
  }

  /// Starts silent update checking at launch and every [kCheckInterval].
  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    if (isMacOSPlatform) {
      await _configureMacOSFeed();
    }
    unawaited(_checkQuietly());
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      kCheckInterval,
      (_) => unawaited(_checkQuietly()),
    );
  }

  /// Checks now and opens the update prompt when a newer build is found.
  Future<void> checkNow({BuildContext? context}) async {
    if (!supported) return;
    if (isMacOSPlatform) {
      await _configureMacOSFeed();
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

  /// Opens the update UI for an update already discovered in the background.
  Future<void> installAvailable({BuildContext? context}) async {
    if (!supported) return;
    if (isMacOSPlatform) {
      await checkNow(context: context);
      return;
    }
    final entry = availableUpdate.value;
    final updater = _createLinuxUpdater();
    final ctx = context ?? _contextProvider?.call();
    if (entry == null || updater == null || ctx == null || !ctx.mounted) return;
    await _promptAndInstall(ctx, updater, entry);
  }

  Future<void> _configureMacOSFeed() async {
    if (_macConfigured) return;
    _macConfigured = true;
    try {
      await autoUpdater.setFeedURL(kAppcastUrl);
    } catch (error) {
      _macConfigured = false;
      debugPrint('Updates could not configure feed: $error');
    }
  }

  LinuxSelfUpdater? _createLinuxUpdater() {
    final path = currentAppImagePath;
    if (path == null) return null;
    return LinuxSelfUpdater(appImagePath: path);
  }

  Future<void> _checkQuietly() async {
    if (_busy) return;
    try {
      final AppcastEntry? entry;
      if (isMacOSPlatform) {
        entry = await fetchNewerAppcastEntry(
          feedUri: Uri.parse(kAppcastUrl),
          os: 'macos',
        );
      } else if (isLinuxPlatform) {
        final updater = _createLinuxUpdater();
        if (updater == null) return;
        entry = await updater.checkForUpdate();
      } else {
        return;
      }
      availableUpdate.value = entry;
    } catch (error) {
      debugPrint('Background update check failed: $error');
    }
  }

  Future<void> _checkLinuxNow(BuildContext? ctx) async {
    final updater = _createLinuxUpdater();
    if (updater == null || _busy) return;
    _busy = true;
    AppcastEntry? entry;
    try {
      entry = await updater.checkForUpdate();
      availableUpdate.value = entry;
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
    final progress = ValueNotifier<LinuxUpdateProgress>(
      LinuxUpdateProgress(
        stage: LinuxUpdateStage.downloading,
        received: 0,
        total: entry.length,
      ),
    );
    final cancelToken = LinuxUpdateCancelToken();
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => UpdateDownloadDialog(
        version: entry.version,
        progress: progress,
        onCancel: cancelToken.cancel,
      ),
    ).whenComplete(() => dialogOpen = false);

    try {
      await updater.downloadAndInstall(
        entry,
        onProgress: (snap) => progress.value = snap,
        cancelToken: cancelToken,
      );
    } on LinuxUpdateCancelledException {
      _busy = false;
      if (dialogOpen && ctx.mounted) {
        Navigator.of(ctx, rootNavigator: true).pop();
      }
      await dialogFuture;
      progress.dispose();
      return;
    } catch (error) {
      debugPrint('Update install failed: $error');
      _busy = false;
      if (dialogOpen && ctx.mounted) {
        Navigator.of(ctx, rootNavigator: true).pop();
      }
      await dialogFuture;
      progress.dispose();
      if (ctx.mounted) {
        AppNotifications.error(ctx, t.updates.installFailed);
      }
      return;
    }
    _busy = false;
    if (dialogOpen && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
    await dialogFuture;
    progress.dispose();

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

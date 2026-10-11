import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The two platforms the app ships on, read off [defaultTargetPlatform] so a
/// test can override them. Named getters rather than a comparison spelled out
/// at every call site: most of what branches on the platform is a system-owned
/// feature one of them does not have, and those reads outnumber the places
/// that care which platform it actually is.
///
/// Screens and widgets do not read these. They ask [platformHas] whether the
/// system can do something, or [isDesktopPlatform] whether the user is on a
/// mouse and a keyboard - `test/architecture/platform_branching_test.dart`
/// keeps the rest of `lib/` from spelling the platform out.
bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isIOSPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get isMacOSPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool get isWindowsPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get isLinuxPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

/// True on a windowed desktop OS (Linux/macOS/Windows): a resizable window
/// driven by a mouse and a physical keyboard rather than a single full-screen
/// touch surface. That, not the window's shape, is what decides dialogs over
/// bottom sheets, pages opened beside the sidebar instead of over it, keyboard
/// shortcuts and right-click menus, and no on-screen key toolbar.
bool get isDesktopPlatform =>
    isLinuxPlatform || isMacOSPlatform || isWindowsPlatform;

/// Something the system either can or cannot do. One table, [platformHas],
/// answers for every platform - a new platform is one pass down this list,
/// and a new feature is a compile error until every platform has an answer.
enum PlatformFeature {
  /// A service that keeps sessions alive with the app in the background.
  foregroundService,

  /// The system's per-app battery restriction, which can kill that service.
  batteryOptimization,

  /// The OS suspends the app shortly after it leaves the screen.
  backgroundSuspension,

  /// Local notifications that need the user's permission.
  notificationPermission,

  /// The system asks before the app reaches the local network.
  localNetworkPermission,

  /// Fingerprint or face unlock through `local_auth`.
  biometrics,

  /// Home-screen shortcuts on the app icon.
  quickActions,

  /// The store's in-app review prompt.
  inAppReview,

  /// `webview_flutter` has an implementation here.
  embeddedWebView,

  /// The system share sheet.
  systemShare,

  /// The user can choose the folder downloads are saved to.
  downloadFolderPicker,

  /// A saved file can be shown in the system's file manager.
  revealInFileManager,

  /// Vibration feedback.
  haptics,

  /// The on-screen key toolbar, the floating action dock and every setting
  /// that only matters to a thumb: they stand in for a keyboard and a pointer
  /// the desktop already has.
  touchControls,

  /// The app draws its own title bar in place of the system's.
  customWindowChrome,

    /// The menu bar along the top of the screen that the system owns.
  nativeMenuBar,

  /// The user keeps their own SSH keys in a `.ssh` folder the app can look
  /// in. A phone has no such folder to look in.
  localSshFolder,
}

bool platformHas(PlatformFeature feature) => switch (feature) {
  PlatformFeature.foregroundService => isAndroidPlatform,
  PlatformFeature.batteryOptimization => isAndroidPlatform,
  PlatformFeature.backgroundSuspension => isIOSPlatform,
  PlatformFeature.notificationPermission => isAndroidPlatform || isIOSPlatform,
  PlatformFeature.localNetworkPermission => isAndroidPlatform || isIOSPlatform,
  PlatformFeature.biometrics =>
    isAndroidPlatform || isIOSPlatform || isMacOSPlatform || isWindowsPlatform,
  PlatformFeature.quickActions => isAndroidPlatform || isIOSPlatform,
  PlatformFeature.inAppReview => isAndroidPlatform || isIOSPlatform,
  PlatformFeature.embeddedWebView =>
    isAndroidPlatform || isIOSPlatform || isMacOSPlatform,
  PlatformFeature.systemShare =>
    isAndroidPlatform || isIOSPlatform || isMacOSPlatform,
  PlatformFeature.downloadFolderPicker =>
    isAndroidPlatform || isDesktopPlatform,
  PlatformFeature.revealInFileManager => isDesktopPlatform,
  PlatformFeature.haptics => isAndroidPlatform || isIOSPlatform,
  PlatformFeature.touchControls => !isDesktopPlatform,
  PlatformFeature.customWindowChrome => isDesktopPlatform,
    PlatformFeature.nativeMenuBar => isMacOSPlatform,
  PlatformFeature.localSshFolder => isDesktopPlatform,
};

/// True when there's enough room for the sidebar layout: a desktop window,
/// or any device turned to landscape - width freed up from the side, rather
/// than the bottom nav eating into height that's already short.
bool isWideLayout(BuildContext context) {
  if (isDesktopPlatform) return true;
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height;
}

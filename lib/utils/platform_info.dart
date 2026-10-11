import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The two platforms the app ships on, read off [defaultTargetPlatform] so a
/// test can override them. Named getters rather than a comparison spelled out
/// at every call site: most of what branches on the platform is a system-owned
/// feature one of them does not have, and those reads outnumber the places
/// that care which platform it actually is.
bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isIOSPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// True on a windowed desktop OS (Linux/macOS/Windows), where the app runs
/// in a resizable window with a mouse and keyboard rather than as a single
/// full-screen mobile surface - that's what decides a fixed-height app bar
/// vs. one that collapses on scroll.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);

/// True when there's enough room for the desktop sidebar layout: a desktop
/// window, or any device turned to landscape - width freed up from the
/// side, rather than the bottom nav eating into height that's already
/// short.
bool isWideLayout(BuildContext context) {
  if (isDesktopPlatform) return true;
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height;
}

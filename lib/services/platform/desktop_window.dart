import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../utils/platform_info.dart';

/// Where the window was and how big, so the next launch opens it there.
/// Device state - a backup restored onto another machine with another screen
/// has no use for it - so it is kept in its own keys, outside every
/// `Setting` that goes into a backup.
const kWindowBoundsPrefsKey = 'desktop_window_bounds';
const kWindowMaximizedPrefsKey = 'desktop_window_maximized';

/// Smallest window the layout is drawn for: the sidebar collapsed, a session
/// of a usable 80 columns beside it, and the title bar's controls.
const kMinimumWindowSize = Size(760, 520);
const kDefaultWindowSize = Size(1280, 820);

/// The desktop window: the system's title bar traded for the app's own,
/// a minimum size, and the size and position it had last time.
class DesktopWindow with WindowListener {
  DesktopWindow._();

  static final instance = DesktopWindow._();

  /// Maximized or not, for the title bar's maximize button and the resize
  /// edges, which a maximized window has none of.
  final maximized = ValueNotifier<bool>(false);

  /// Whether the window has the focus - the title bar dims when it does not,
  /// as the system's own did.
  final focused = ValueNotifier<bool>(true);

  Timer? _saveTimer;
  bool _ready = false;

  /// Hides the system's title bar for the app's own. The traffic lights stay
  /// on a Mac, drawn by the system over the space the title bar leaves for
  /// them.
  Future<void> init() async {
    if (!platformHas(PlatformFeature.customWindowChrome)) return;
    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final bounds = _decode(prefs.getString(kWindowBoundsPrefsKey));
    final wasMaximized = prefs.getBool(kWindowMaximizedPrefsKey) ?? false;

    final options = WindowOptions(
      title: 'Termphin',
      size: bounds?.size ?? kDefaultWindowSize,
      minimumSize: kMinimumWindowSize,
      center: bounds == null,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: isMacOSPlatform,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (bounds != null) await windowManager.setPosition(bounds.topLeft);
      if (wasMaximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
      maximized.value = await windowManager.isMaximized();
      _ready = true;
    });
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  /// What closing the window does, set by whoever owns the tray. Unset, it
  /// quits.
  Future<void> Function()? onCloseRequested;

  /// Brings the window back from the tray, from behind other windows, or
  /// from being minimized.
  Future<void> show() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hide() => windowManager.hide();

  Future<bool> get isVisible => windowManager.isVisible();

  /// Ends the process, past the close the window would otherwise intercept.
  Future<void> quit() async {
    _saveTimer?.cancel();
    await _save();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> setTitle(String title) async {
    if (!_ready) return;
    await windowManager.setTitle(title);
  }

  Future<void> minimize() => windowManager.minimize();

  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> close() => windowManager.close();

  @override
  void onWindowMaximize() {
    maximized.value = true;
    _scheduleSave();
  }

  @override
  void onWindowUnmaximize() {
    maximized.value = false;
    _scheduleSave();
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowClose() {
    final handler = onCloseRequested;
    unawaited(handler == null ? quit() : handler());
  }

  @override
  void onWindowFocus() => focused.value = true;

  @override
  void onWindowBlur() => focused.value = false;

  /// A drag reports every pixel; only where it ends is worth writing.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  /// Stores whether the window is maximized, and its bounds only when it is
  /// not: a maximized window's bounds are the screen's, and the ones worth
  /// keeping are those it will go back to.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final isMaximized = await windowManager.isMaximized();
    await prefs.setBool(kWindowMaximizedPrefsKey, isMaximized);
    if (isMaximized) return;
    final bounds = await windowManager.getBounds();
    await prefs.setString(kWindowBoundsPrefsKey, _encode(bounds));
  }

  static String _encode(Rect r) =>
      [r.left, r.top, r.width, r.height].map((v) => v.round()).join(',');

  static Rect? _decode(String? value) {
    if (value == null) return null;
    final parts = value.split(',').map(double.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return null;
    final rect = Rect.fromLTWH(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
    if (rect.width < kMinimumWindowSize.width ||
        rect.height < kMinimumWindowSize.height) {
      return null;
    }
    return rect;
  }
}

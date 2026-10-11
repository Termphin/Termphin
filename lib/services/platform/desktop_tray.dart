import 'package:flutter/foundation.dart';
import 'package:tray_kit/tray_kit.dart';

import '../../utils/platform_info.dart';
import 'tray_menu.dart';

/// Draws the tray icon and its menu.
abstract class TrayBackend {
  /// Whether this desktop has a tray at all.
  Future<bool> isAvailable();

  /// Puts the icon up, or redraws it.
  Future<void> show({
    required List<TrayMenuEntry> menu,
    required String tooltip,
    required VoidCallback onActivate,
  });

  Future<void> hide();
}

/// The tray, as the rest of the app sees it.
class DesktopTray {
  DesktopTray._(this._backend);

  static final instance = DesktopTray._(
    isDesktopPlatform ? TrayKitBackend() : null,
  );

  @visibleForTesting
  factory DesktopTray.test(TrayBackend backend) => DesktopTray._(backend);

  final TrayBackend? _backend;
  bool? _available;
  bool _shown = false;

  /// Asked once per run.
  Future<bool> get available async {
    final backend = _backend;
    if (backend == null) return false;
    return _available ??= await backend.isAvailable();
  }

  bool get shown => _shown;

  /// Shows the icon; a tray that refuses it counts as no tray from then on,
  /// so closing the window quits instead of hiding it.
  Future<void> show({
    required List<TrayMenuEntry> menu,
    required String tooltip,
    required VoidCallback onActivate,
  }) async {
    final backend = _backend;
    if (backend == null || !await available) return;
    try {
      await backend.show(menu: menu, tooltip: tooltip, onActivate: onActivate);
      _shown = true;
    } on Object {
      _available = false;
      _shown = false;
      await backend.hide().catchError((Object _) {});
    }
  }

  Future<void> hide() async {
    if (!_shown) return;
    _shown = false;
    await _backend?.hide();
  }
}

/// [TrayBackend] over `tray_kit`.
class TrayKitBackend implements TrayBackend {
  TrayKitBackend({TrayKit? tray}) : _tray = tray ?? TrayKit.instance;

  final TrayKit _tray;
  TrayIcon? _icon;

  @override
  Future<bool> isAvailable() => _tray.isSupported();

  @override
  Future<void> show({
    required List<TrayMenuEntry> menu,
    required String tooltip,
    required VoidCallback onActivate,
  }) async {
    await _tray.show(
      icon: _icon ??= await _loadIcon(),
      tooltip: tooltip,
      menu: toTrayMenu(menu),
      onActivate: onActivate,
    );
  }

  @override
  Future<void> hide() => _tray.hide();

  static Future<TrayIcon> _loadIcon() => isMacOSPlatform
      ? TrayIcon.asset('assets/icons/tray_template.png', isTemplate: true)
      : TrayIcon.asset('assets/icons/tray.png');

  @visibleForTesting
  static List<TrayMenuItem> toTrayMenu(List<TrayMenuEntry> entries) => [
    for (final entry in entries)
      if (entry.separator)
        const TrayMenuSeparator()
      else if (entry.children.isNotEmpty)
        TraySubmenu(
          entry.label,
          toTrayMenu(entry.children),
          enabled: entry.enabled,
        )
      else
        TrayMenuAction(
          entry.label,
          onSelected: entry.onSelected,
          enabled: entry.enabled,
        ),
  ];
}

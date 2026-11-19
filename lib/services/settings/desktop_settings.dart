import 'setting.dart';

/// Whether closing the window leaves Termphin running in the tray, its
/// sessions connected, rather than quitting. On by default: a closed window
/// dropping every connection behind it is the surprise, not the other way
/// round. Only asked where there is a tray to keep it in - see `DesktopTray`.
final Setting<bool> closeToTraySetting = Setting.boolean(
  'desktop_close_to_tray',
  fallback: true,
);

import 'setting.dart';

/// Where the terminal's tab strip sits in portrait. At the bottom it is the
/// lowest thing above the key toolbar, or above the screen's edge where
/// there is no toolbar (the file browser) - in reach of a thumb on a tall
/// phone. Landscape has the side rail either way.
enum TabBarPosition { top, bottom }

final Setting<TabBarPosition> tabBarPositionSetting = Setting.option(
  'terminal_tab_bar_position',
  fallback: TabBarPosition.top,
  values: TabBarPosition.values,
);

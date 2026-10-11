import 'setting.dart';

/// Which edge the dock is docked to. Only left/right - top and bottom would
/// put it over the tab strip or the special-keys toolbar.
enum FloatingDockSide { left, right }

const kFloatingDockSidePrefsKey = 'floating_action_dock_side';

/// Vertical position along the docked edge, as a fraction of the available
/// height (0 = top, 1 = bottom) - free-form, unlike the side.
const kFloatingDockVerticalFractionPrefsKey =
    'floating_action_dock_vertical_fraction';

const kFloatingDockEnabledPrefsKey = 'floating_action_dock_enabled';

/// Where the dock sits and whether it is shown at all.
///
/// [enabled] is watched by the terminal, so a toggle flipped in settings
/// reaches an open session without it having to be reopened.
class FloatingDockSettings {
  FloatingDockSettings._();

  static final FloatingDockSettings instance = FloatingDockSettings._();

  /// Untracked, like [verticalFraction]: both are rewritten at the end of
  /// every drag of the button, which is a gesture rather than a settings
  /// choice, or the settings-changed stream would be almost entirely dock
  /// coordinates.
  final side = Setting.option(
    kFloatingDockSidePrefsKey,
    fallback: FloatingDockSide.right,
    values: FloatingDockSide.values,
    track: false,
  );

  final verticalFraction = Setting.number(
    kFloatingDockVerticalFractionPrefsKey,
    fallback: 0.5,
    min: 0,
    max: 1,
    track: false,
  );

  final enabled = Setting.boolean(kFloatingDockEnabledPrefsKey, fallback: true);

  List<Setting<Object?>> get all => [side, verticalFraction, enabled];

  Future<void> load() async {
    await Future.wait([for (final setting in all) setting.load()]);
  }
}

FloatingDockSettings get floatingDockSettings => FloatingDockSettings.instance;

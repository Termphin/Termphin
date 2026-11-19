import 'setting.dart';

const kSidebarCollapsedPrefsKey = 'sidebar_collapsed';

/// Whether the wide-layout side rail is collapsed to icons only.
///
/// One setting for both rails, not one each: `MainShell`'s nav rail and
/// `TerminalScreen`'s tab rail are the same 240pt strip down the same edge
/// and are never on screen together, so collapsing one and finding the other
/// still full width would read as the sidebar forgetting what it was told.
final Setting<bool> sidebarCollapsedSetting = Setting.boolean(
  kSidebarCollapsedPrefsKey,
  fallback: false,
);

const kSidebarWidthPrefsKey = 'sidebar_width';

/// The narrowest and widest a desktop sidebar can be dragged to: under the
/// first a label has no room left, over the second it is taking the window
/// from what it navigates.
const double kSidebarMinWidth = 180;
const double kSidebarMaxWidth = 420;

/// The width a desktop sidebar was dragged to, labels showing.
///
/// Device state like the window's own bounds, so it stays out of the backup:
/// it fits this screen, not the one a backup is restored on.
final Setting<double> sidebarWidthSetting = Setting.number(
  kSidebarWidthPrefsKey,
  fallback: 240,
  min: kSidebarMinWidth,
  max: kSidebarMaxWidth,
  track: false,
);

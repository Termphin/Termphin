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

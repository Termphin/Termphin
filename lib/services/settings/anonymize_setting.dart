import 'setting.dart';

/// Named for what it used to be; kept so the setting survives the rename.
const kAnonymizePrefsKey = 'anonymize_screenshots';

/// Whether machine names, hosts and usernames render as deterministic
/// placeholders instead of the real values - display only, for anyone who can
/// see the screen. Nothing in storage changes, so a session stays connected to
/// the real host throughout.
final Setting<bool> anonymizeSetting = Setting.boolean(
  kAnonymizePrefsKey,
  fallback: false,
);

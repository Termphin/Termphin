import 'setting.dart';

/// Whether the machine form opens with its "More options" shown: fallback
/// hosts, jump host, port forwarding and server notifications.
///
/// Follows the user rather than being chosen in Settings: opening the
/// section in the form turns it on, closing it turns it off, so whoever
/// keeps reaching for those options stops having to. Written by a gesture
/// rather than chosen, so it is not reported as a settings change; backed
/// up like the sidebar's collapsed state, as a preference.
final Setting<bool> profileFormMoreOptionsSetting = Setting.boolean(
  'profile_form_more_options',
  fallback: false,
  track: false,
);

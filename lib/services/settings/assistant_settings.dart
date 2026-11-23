import 'setting.dart';

/// Whether Phin, the assistant, is there at all. Off hides it everywhere -
/// no orb over the terminal, nothing sent anywhere.
final Setting<bool> phinEnabledSetting = Setting.boolean(
  'phin_enabled',
  fallback: true,
);

/// Whether Phin keeps short notes about each server between conversations.
/// Off stops it saving new ones and sending the saved ones; what it already
/// saved stays until the user forgets it.
final Setting<bool> phinMemorySetting = Setting.boolean(
  'phin_memory',
  fallback: true,
);

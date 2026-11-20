import 'setting.dart';

/// Whether live status is on: the account's machines report which sessions
/// they hold and what those are doing, and this device shows it without
/// connecting. Off until the user turns it on in the account, because it
/// puts a line in each machine's crontab.
final Setting<bool> livePresenceSetting = Setting.boolean(
  'live_presence',
  fallback: false,
);

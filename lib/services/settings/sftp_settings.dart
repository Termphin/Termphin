import 'setting.dart';

/// Whether the SFTP browser lists dotfiles. The browser's eye button and the
/// switch in Settings are this one setting; the key predates it.
final sftpShowHiddenSetting = Setting.boolean(
  'sftp_show_hidden',
  fallback: false,
);

/// Whether switching a session to files opens the directory its shell is in.
/// Only a session with the agent (or a Windows prompt reporting itself) knows
/// that; any other opens at home either way.
final sftpFollowTerminalSetting = Setting.boolean(
  'sftp_follow_terminal',
  fallback: true,
);

enum SftpSortField { name, size, modified }

/// What the SFTP browser sorts by. Not reported to analytics: it was a plain
/// preference before it was a setting, and a sort is a gesture, not a choice
/// worth counting.
final sftpSortFieldSetting = Setting.option(
  'sftp_sort_field',
  fallback: SftpSortField.name,
  values: SftpSortField.values,
  track: false,
);

final sftpSortDescendingSetting = Setting.boolean(
  'sftp_sort_desc',
  fallback: false,
  track: false,
);

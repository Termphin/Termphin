import 'package:flutter/foundation.dart';

import 'setting.dart';

const kTerminalSchemePrefsKey = 'terminal_scheme';
const kTerminalLineHeightPrefsKey = 'terminal_line_height';
const kTerminalSidePaddingPrefsKey = 'terminal_side_padding';
const kTerminalFontSizePrefsKey = 'terminal_font_size';
const kTerminalCursorStylePrefsKey = 'terminal_cursor_style';
const kTerminalCursorBlinkPrefsKey = 'terminal_cursor_blink';
const kTerminalFontFamilyPrefsKey = 'terminal_font_family';
const kTerminalPredictiveEchoPrefsKey = 'terminal_predictive_echo';
const kTerminalProgramNotificationsPrefsKey = 'terminal_program_notifications';
const kTerminalFinishedNotificationsPrefsKey =
    'terminal_finished_notifications';
const kTerminalQuietNotificationsPrefsKey = 'terminal_quiet_notifications';
const kTerminalNoticeLinesPrefsKey = 'terminal_notice_lines';
const kTerminalOpenAppNoticesPrefsKey = 'terminal_open_app_notices';
const kTerminalOpenAppNoticeStylePrefsKey = 'terminal_open_app_notice_style';

/// [TerminalSettings.openAppNoticeStyle]: the app's own card.
const kOpenAppNoticeInApp = 'app';

/// [TerminalSettings.openAppNoticeStyle]: the system's notification.
const kOpenAppNoticeSystem = 'system';

/// Dark first, then the light ones - several are the light flavour of a dark
/// scheme above (Tokyo Night Day, Alucard, Latte), which is why they are
/// listed as their own entries rather than derived from a switch.
const Map<String, String> kTerminalSchemeLabels = {
  'default': 'Default',
  'tokyo-night': 'Tokyo Night',
  'dracula': 'Dracula',
  'nord': 'Nord',
  'gruvbox': 'Gruvbox',
  'one-dark': 'One Dark',
  'catppuccin': 'Catppuccin Mocha',
  'matrix': 'Matrix',
  'light': 'Light',
  'tokyo-night-day': 'Tokyo Night Day',
  'alucard': 'Alucard (Dracula Light)',
  'gruvbox-light': 'Gruvbox Light',
  'one-light': 'One Light',
  'catppuccin-latte': 'Catppuccin Latte',
};

const List<String> kCursorStyles = ['block', 'bar', 'underline'];

/// The pinch-zoom range on an open session, which is the same preference the
/// appearance screen's stepper writes.
const double kTerminalDefaultFontSize = 12;
const double kTerminalMinFontSize = 8;
const double kTerminalMaxFontSize = 24;

/// Nerd Font variants - same glyphs as the plain font plus the
/// Powerline/Devicons/symbol sets full-screen TUIs rely on for status icons.
const Map<String, String> kTerminalFontLabels = {
  'HackNerdFontMono': 'Hack',
  'JetBrainsMonoNerdFontMono': 'JetBrains Mono',
  'FiraCodeNerdFontMono': 'Fira Code',
  'UbuntuMonoNerdFontMono': 'Ubuntu Mono',
  'SauceCodeProNerdFontMono': 'Source Code Pro',
};

/// Everything the terminal is drawn with. Each field is its own [Setting], so
/// a screen that only changes the font size does not have to load, rebuild and
/// rewrite the other six.
class TerminalSettings {
  TerminalSettings._();

  static final TerminalSettings instance = TerminalSettings._();

  final scheme = Setting.text(
    kTerminalSchemePrefsKey,
    fallback: 'default',
    allowed: kTerminalSchemeLabels.keys.toSet(),
  );

  final lineHeight = Setting.number(
    kTerminalLineHeightPrefsKey,
    fallback: 1.0,
    min: 1.0,
    max: 2.0,
  );

  final sidePadding = Setting.number(
    kTerminalSidePaddingPrefsKey,
    fallback: 6,
    min: 0,
    max: 16,
  );

  /// Written from the terminal itself as well as from settings - a pinch
  /// zoom on an open session is the same preference as the stepper.
  final fontSize = Setting.number(
    kTerminalFontSizePrefsKey,
    fallback: kTerminalDefaultFontSize,
    min: kTerminalMinFontSize,
    max: kTerminalMaxFontSize,
  );

  final cursorStyle = Setting.text(
    kTerminalCursorStylePrefsKey,
    fallback: 'block',
    allowed: kCursorStyles.toSet(),
  );

  final cursorBlink = Setting.boolean(
    kTerminalCursorBlinkPrefsKey,
    fallback: true,
  );

  /// Draws typed characters before the server echoes them. Only ever visible
  /// on a slow link, so on by default.
  final predictiveEcho = Setting.boolean(
    kTerminalPredictiveEchoPrefsKey,
    fallback: true,
  );

  /// Shows what a program asks the terminal to announce - Claude Code done
  /// or waiting, `termphin notify` at the end of a build - as a system
  /// notification, when its session is not the one on screen.
  final programNotifications = Setting.boolean(
    kTerminalProgramNotificationsPrefsKey,
    fallback: true,
  );

  /// Shows a command the agent saw run for a long time as finished, when its
  /// session is not the one on screen.
  final finishedNotifications = Setting.boolean(
    kTerminalFinishedNotificationsPrefsKey,
    fallback: true,
  );

  /// Shows a program the agent saw stop and wait as possibly needing the
  /// user, when its session is not the one on screen.
  final quietNotifications = Setting.boolean(
    kTerminalQuietNotificationsPrefsKey,
    fallback: true,
  );

  /// Whether the agent's notifications quote the last line a command printed,
  /// which then passes through the relay and shows on the lock screen.
  final noticeLines = Setting.boolean(
    kTerminalNoticeLinesPrefsKey,
    fallback: true,
  );

  /// Whether a session that is not on screen notifies at all while
  /// Termphin is in front. In the background it always does.
  final openAppNotices = Setting.boolean(
    kTerminalOpenAppNoticesPrefsKey,
    fallback: true,
  );

  /// How [openAppNotices] shows them: [kOpenAppNoticeInApp], the app's own
  /// card at the top of the screen with a buzz, or [kOpenAppNoticeSystem],
  /// the system's notification as in the background.
  final openAppNoticeStyle = Setting.text(
    kTerminalOpenAppNoticeStylePrefsKey,
    fallback: kOpenAppNoticeInApp,
    allowed: const {kOpenAppNoticeInApp, kOpenAppNoticeSystem},
  );

  final fontFamily = Setting.text(
    kTerminalFontFamilyPrefsKey,
    fallback: 'HackNerdFontMono',
    allowed: kTerminalFontLabels.keys.toSet(),
  );

  List<Setting<Object?>> get all => [
    scheme,
    lineHeight,
    sidePadding,
    fontSize,
    cursorStyle,
    cursorBlink,
    predictiveEcho,
    programNotifications,
    finishedNotifications,
    quietNotifications,
    noticeLines,
    openAppNotices,
    openAppNoticeStyle,
    fontFamily,
  ];

  /// Fires whenever any of them changes, so an open session can re-read the
  /// lot without subscribing to each one. This is what the old
  /// `terminalSettingsVersion` counter existed to do; the difference is that
  /// nothing has to remember to bump it.
  late final Listenable changes = Listenable.merge(all);

  Future<void> load() async {
    await Future.wait([for (final setting in all) setting.load()]);
  }
}

/// Shorthand for the singleton - this is read from enough places that
/// spelling out `TerminalSettings.instance` every time buries the field being
/// read.
TerminalSettings get terminalSettings => TerminalSettings.instance;

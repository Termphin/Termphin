import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_info.dart';
import 'terminal_color_scheme.dart';
import 'terminal_color_schemes.dart' as schemes;

export 'terminal_color_scheme.dart';
export 'terminal_color_schemes.dart';

/// Every colour the interface draws with, in one of two instances.
///
/// Read it off the context (`context.colors`) rather than as a constant: that
/// is what makes a widget a dependent of the theme, so it repaints when the
/// user - or the system - switches between light and dark.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.primary,
    required this.primaryHover,
    required this.primaryActive,
    required this.primaryHighlight,
    required this.primaryMuted,
    required this.backgroundPrimary,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.surfaceOffset,
    required this.surfaceOffset2,
    required this.surfaceDynamic,
    required this.surfaceDivider,
    required this.surfaceBorder,
    required this.surfaceBorderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.onPrimary,
    required this.success,
    required this.successHover,
    required this.successActive,
    required this.successHighlight,
    required this.error,
    required this.errorHover,
    required this.errorActive,
    required this.errorHighlight,
    required this.warning,
    required this.warningHover,
    required this.warningActive,
    required this.warningHighlight,
  });

  final Brightness brightness;

  final Color primary;
  final Color primaryHover;
  final Color primaryActive;
  final Color primaryHighlight;
  final Color primaryMuted;

  final Color backgroundPrimary;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color surfaceOffset;
  final Color surfaceOffset2;
  final Color surfaceDynamic;
  final Color surfaceDivider;

  /// The quiet hairline every container gets. Separation is mostly the step
  /// between [surfaceCard] and [backgroundPrimary]; the border only confirms
  /// the edge, so it stays a shade away from its own surface rather than a
  /// stroke drawn around everything.
  final Color surfaceBorder;

  /// For edges that have to hold on their own: menus, dialogs and sheets
  /// floating over a scrim, and whatever is currently selected.
  final Color surfaceBorderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color onPrimary;

  final Color success;
  final Color successHover;
  final Color successActive;
  final Color successHighlight;

  final Color error;
  final Color errorHover;
  final Color errorActive;
  final Color errorHighlight;

  final Color warning;
  final Color warningHover;
  final Color warningActive;
  final Color warningHighlight;

  bool get isDark => brightness == Brightness.dark;

  /// Fill for the controls a form is made of - fields, dropdowns, pickers.
  /// Dark steps them up off whatever they sit on, since a card and a field
  /// painted the same colour only differ by their hairline. Light keeps them
  /// white and lets the border do it, the way a page of forms reads.
  Color get fieldFill => isDark ? surfaceOffset : surfaceCard;

  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    primary: Color(0xFF4A9BF0),
    primaryHover: Color(0xFF7FBCF8),
    primaryActive: Color(0xFF2E86DE),
    primaryHighlight: Color(0xFF12243A),
    primaryMuted: Color(0xFF2E6296),
    backgroundPrimary: Color(0xFF080C10),
    surfaceCard: Color(0xFF131C23),
    surfaceElevated: Color(0xFF1A242C),
    surfaceOffset: Color(0xFF202C35),
    surfaceOffset2: Color(0xFF27353F),
    surfaceDynamic: Color(0xFF33434F),
    surfaceDivider: Color(0xFF1B252D),
    surfaceBorder: Color(0xFF24323C),
    surfaceBorderStrong: Color(0xFF31404B),
    textPrimary: Color(0xFFE4EBF0),
    textSecondary: Color(0xFF9FACB6),
    textTertiary: Color(0xFF7A8791),
    textInverse: Color(0xFF071016),
    onPrimary: Color(0xFF06121C),
    success: Color(0xFF5CCB93),
    successHover: Color(0xFF22C55E),
    successActive: Color(0xFF16A34A),
    successHighlight: Color(0xFF0D1F14),
    error: Color(0xFFF17A7A),
    errorHover: Color(0xFFEF4444),
    errorActive: Color(0xFFDC2626),
    errorHighlight: Color(0xFF1F0D0D),
    warning: Color(0xFFEBB55A),
    warningHover: Color(0xFFF59E0B),
    warningActive: Color(0xFFD97706),
    warningHighlight: Color(0xFF1E1808),
  );

  /// The dark palette read back off a white page: the same hues, moved to the
  /// contrast they need against a light background rather than simply
  /// inverted, so the blue still reads as the same brand blue.
  static const AppColors light = AppColors(
    brightness: Brightness.light,
    primary: Color(0xFF0C63CE),
    primaryHover: Color(0xFF0A54B0),
    primaryActive: Color(0xFF08458F),
    primaryHighlight: Color(0xFFCEE0F8),
    primaryMuted: Color(0xFFA8C8EF),
    backgroundPrimary: Color(0xFFEFF3F7),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceOffset: Color(0xFFE9EEF4),
    surfaceOffset2: Color(0xFFDEE5EC),
    surfaceDynamic: Color(0xFFC8D2DC),
    surfaceDivider: Color(0xFFEBEFF4),
    surfaceBorder: Color(0xFFDFE5EC),
    surfaceBorderStrong: Color(0xFFC9D3DD),
    textPrimary: Color(0xFF18242F),
    textSecondary: Color(0xFF46545F),
    textTertiary: Color(0xFF68757F),
    textInverse: Color(0xFFF8FAFC),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    successHover: Color(0xFF16A34A),
    successActive: Color(0xFF166534),
    successHighlight: Color(0xFFE8F6ED),
    error: Color(0xFFC92A2A),
    errorHover: Color(0xFFB01F1F),
    errorActive: Color(0xFF8F1A1A),
    errorHighlight: Color(0xFFFBEBEB),
    warning: Color(0xFFA75C0A),
    warningHover: Color(0xFF8A4B08),
    warningActive: Color(0xFF6E3C06),
    warningHighlight: Color(0xFFFBF2E2),
  );

  /// The interface palette a terminal colour scheme implies, for the chrome
  /// wrapped around a session - tab strip, key toolbar, dock, sheets.
  ///
  /// Everything is derived from the scheme's own background, foreground and
  /// ANSI colours rather than taken from its `ui*` fields, so the same
  /// contrast ratios the app palettes are tuned to hold in every scheme,
  /// including the ones written for a terminal and nothing else.
  factory AppColors.fromTerminalScheme(TerminalColorScheme s) {
    final bg = s.background;
    final fg = s.foreground;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    final isDark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    final surface = mix(bg, fg, 0.05);
    Color onAccent(Color accent) =>
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? s.brightWhite
        : s.black;
    return AppColors(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: s.blue,
      primaryHover: s.brightBlue,
      primaryActive: mix(s.blue, bg, 0.25),
      primaryHighlight: mix(bg, s.blue, 0.16),
      primaryMuted: mix(s.blue, bg, 0.45),
      backgroundPrimary: bg,
      surfaceCard: surface,
      surfaceElevated: mix(bg, fg, 0.09),
      surfaceOffset: mix(bg, fg, 0.13),
      surfaceOffset2: mix(bg, fg, 0.19),
      surfaceDynamic: mix(bg, fg, 0.28),
      surfaceDivider: mix(bg, fg, 0.10),
      surfaceBorder: mix(bg, fg, 0.15),
      surfaceBorderStrong: mix(bg, fg, 0.27),
      textPrimary: fg,
      textSecondary: _fade(fg, bg, 0.28, 4),
      textTertiary: _fade(fg, bg, 0.46, 3),
      textInverse: bg,
      onPrimary: onAccent(s.blue),
      success: s.green,
      successHover: s.brightGreen,
      successActive: mix(s.green, bg, 0.25),
      successHighlight: mix(bg, s.green, 0.14),
      error: s.red,
      errorHover: s.brightRed,
      errorActive: mix(s.red, bg, 0.25),
      errorHighlight: mix(bg, s.red, 0.14),
      warning: s.yellow,
      warningHover: s.brightYellow,
      warningActive: mix(s.yellow, bg, 0.25),
      warningHighlight: mix(bg, s.yellow, 0.14),
    );
  }

  /// [fg] faded [t] of the way into [bg], but no further than the point where
  /// it still clears [floor] against it.
  ///
  /// Schemes differ in how much contrast they start with - Tokyo Night Day
  /// runs its own text at 4.5:1 - so a fixed fade that reads as "muted" in one
  /// is illegible in another. Where a scheme has no room, this gives up the
  /// fade rather than the legibility.
  static Color _fade(Color fg, Color bg, double t, double floor) {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    var faded = t;
    var out = Color.lerp(fg, bg, faded)!;
    while (faded > 0 && ratio(out, bg) < floor) {
      faded -= 0.04;
      out = Color.lerp(fg, bg, math.max(faded, 0))!;
    }
    return out;
  }

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? dark;

  TextStyle get monoStyle => TextStyle(
    fontFamily: AppTheme.monoFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  TextStyle get monoSmall => TextStyle(
    fontFamily: AppTheme.monoFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// [monoStyle]/[monoSmall] metrics in the UI face, for ordinary interface
  /// text that used to be set in monospace. Monospace stays for what is
  /// actually code: commands, keys, logs, paths and editor content.
  TextStyle get uiStyle => TextStyle(
    fontFamily: AppTheme.uiFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  TextStyle get uiSmall => TextStyle(
    fontFamily: AppTheme.uiFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  TextStyle get itemTitle => TextStyle(
    fontFamily: AppTheme.uiFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  TextStyle get sectionLabel => TextStyle(
    fontFamily: AppTheme.uiFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: textTertiary,
  );

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? primary,
    Color? primaryHover,
    Color? primaryActive,
    Color? primaryHighlight,
    Color? primaryMuted,
    Color? backgroundPrimary,
    Color? surfaceCard,
    Color? surfaceElevated,
    Color? surfaceOffset,
    Color? surfaceOffset2,
    Color? surfaceDynamic,
    Color? surfaceDivider,
    Color? surfaceBorder,
    Color? surfaceBorderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? onPrimary,
    Color? success,
    Color? successHover,
    Color? successActive,
    Color? successHighlight,
    Color? error,
    Color? errorHover,
    Color? errorActive,
    Color? errorHighlight,
    Color? warning,
    Color? warningHover,
    Color? warningActive,
    Color? warningHighlight,
  }) {
    return AppColors(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primaryActive: primaryActive ?? this.primaryActive,
      primaryHighlight: primaryHighlight ?? this.primaryHighlight,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceOffset: surfaceOffset ?? this.surfaceOffset,
      surfaceOffset2: surfaceOffset2 ?? this.surfaceOffset2,
      surfaceDynamic: surfaceDynamic ?? this.surfaceDynamic,
      surfaceDivider: surfaceDivider ?? this.surfaceDivider,
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
      surfaceBorderStrong: surfaceBorderStrong ?? this.surfaceBorderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      onPrimary: onPrimary ?? this.onPrimary,
      success: success ?? this.success,
      successHover: successHover ?? this.successHover,
      successActive: successActive ?? this.successActive,
      successHighlight: successHighlight ?? this.successHighlight,
      error: error ?? this.error,
      errorHover: errorHover ?? this.errorHover,
      errorActive: errorActive ?? this.errorActive,
      errorHighlight: errorHighlight ?? this.errorHighlight,
      warning: warning ?? this.warning,
      warningHover: warningHover ?? this.warningHover,
      warningActive: warningActive ?? this.warningActive,
      warningHighlight: warningHighlight ?? this.warningHighlight,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: c(primary, other.primary),
      primaryHover: c(primaryHover, other.primaryHover),
      primaryActive: c(primaryActive, other.primaryActive),
      primaryHighlight: c(primaryHighlight, other.primaryHighlight),
      primaryMuted: c(primaryMuted, other.primaryMuted),
      backgroundPrimary: c(backgroundPrimary, other.backgroundPrimary),
      surfaceCard: c(surfaceCard, other.surfaceCard),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfaceOffset: c(surfaceOffset, other.surfaceOffset),
      surfaceOffset2: c(surfaceOffset2, other.surfaceOffset2),
      surfaceDynamic: c(surfaceDynamic, other.surfaceDynamic),
      surfaceDivider: c(surfaceDivider, other.surfaceDivider),
      surfaceBorder: c(surfaceBorder, other.surfaceBorder),
      surfaceBorderStrong: c(surfaceBorderStrong, other.surfaceBorderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textInverse: c(textInverse, other.textInverse),
      onPrimary: c(onPrimary, other.onPrimary),
      success: c(success, other.success),
      successHover: c(successHover, other.successHover),
      successActive: c(successActive, other.successActive),
      successHighlight: c(successHighlight, other.successHighlight),
      error: c(error, other.error),
      errorHover: c(errorHover, other.errorHover),
      errorActive: c(errorActive, other.errorActive),
      errorHighlight: c(errorHighlight, other.errorHighlight),
      warning: c(warning, other.warning),
      warningHover: c(warningHover, other.warningHover),
      warningActive: c(warningActive, other.warningActive),
      warningHighlight: c(warningHighlight, other.warningHighlight),
    );
  }
}

extension AppColorFade on Color {
  /// This colour at zero alpha.
  ///
  /// What an implicitly animated fill has to tween to instead of
  /// [Colors.transparent]: that constant is transparent *black*, so a colour
  /// animating to it takes its RGB through black on the way out. Over a dark
  /// surface nothing shows; over a light one it is a grey smear that appears
  /// out of nowhere every time the selection moves.
  Color get invisible => withValues(alpha: 0);
}

extension AppColorsContext on BuildContext {
  /// The palette for whichever theme is in force here.
  AppColors get colors => AppColors.of(this);
}

class AppTheme {
  const AppTheme._();

  /// Fixed terminal chrome - the terminal keeps its own colour scheme rather
  /// than following the app palette.
  static const Color terminalBg = kTerminalChromeBackground;
  static const Color terminalFg = kTerminalChromeForeground;
  static const Color terminalCursor = kTerminalChromeCursor;

  static const double radiusXs = 10;
  static const double radiusSm = 14;
  static const double radiusMd = 20;
  static const double radiusLg = 26;
  static const double radiusXl = 32;
  static const double radiusXxl = 40;
  static const double radiusPill = 999;

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration interactiveDuration = Duration(milliseconds: 160);
  static const Duration motionSlow = Duration(milliseconds: 200);
  static const Curve interactiveCurve = Cubic(0.16, 1, 0.3, 1);

  static const TerminalColorScheme terminalSchemeDefault =
      schemes.terminalSchemeDefault;

  static const TerminalColorScheme terminalSchemeLight =
      schemes.terminalSchemeLight;

  static const TerminalColorScheme terminalSchemeTokyoNight =
      schemes.terminalSchemeTokyoNight;

  static const TerminalColorScheme terminalSchemeDracula =
      schemes.terminalSchemeDracula;

  static const TerminalColorScheme terminalSchemeNord =
      schemes.terminalSchemeNord;

  static const TerminalColorScheme terminalSchemeGruvbox =
      schemes.terminalSchemeGruvbox;

  static const TerminalColorScheme terminalSchemeOneDark =
      schemes.terminalSchemeOneDark;

  static const TerminalColorScheme terminalSchemeCatppuccin =
      schemes.terminalSchemeCatppuccin;

  static const TerminalColorScheme terminalSchemeMatrix =
      schemes.terminalSchemeMatrix;

  static const TerminalColorScheme terminalSchemeTokyoNightDay =
      schemes.terminalSchemeTokyoNightDay;

  static const TerminalColorScheme terminalSchemeAlucard =
      schemes.terminalSchemeAlucard;

  static const TerminalColorScheme terminalSchemeGruvboxLight =
      schemes.terminalSchemeGruvboxLight;

  static const TerminalColorScheme terminalSchemeOneLight =
      schemes.terminalSchemeOneLight;

  static const TerminalColorScheme terminalSchemeCatppuccinLatte =
      schemes.terminalSchemeCatppuccinLatte;

  static TerminalColorScheme terminalSchemeForId(String schemeId) =>
      schemes.terminalSchemeForId(schemeId);

  /// Height for chrome that wraps text - bars, docks, menu rows.
  ///
  /// A fixed height is a promise that the text inside still fits, and it stops
  /// being true the moment the user raises their font scale. Growing the box
  /// by the same factor the text grows by keeps the padding around it looking
  /// deliberate at every setting instead of clipping at the large end. The
  /// app-wide clamp in `_ScaledMediaQuery` is what stops this running away.
  static double scaledChrome(BuildContext context, double base) =>
      MediaQuery.textScalerOf(context).scale(base);

  /// Geist is used throughout the interface; terminal content stays monospace.
  static const String headingFamily = 'Geist';
  static const String uiFamily = 'Geist';

  static TextTheme textThemeFor(AppColors c) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: headingFamily,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        color: c.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: headingFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: c.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: headingFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      titleSmall: TextStyle(
        fontFamily: headingFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: uiFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: c.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: uiFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: c.textSecondary,
      ),
      bodySmall: TextStyle(
        fontFamily: uiFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: c.textTertiary,
      ),
      labelLarge: TextStyle(
        fontFamily: uiFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: uiFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: uiFamily,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: c.textTertiary,
      ),
    );
  }

  /// The same face the terminal defaults to, so a host or session name reads
  /// identically whether it is sitting in the UI or echoed by a shell.
  static const String monoFamily = 'HackNerdFontMono';

  static ThemeData get darkTheme => themeFor(AppColors.dark);

  static ThemeData get lightTheme => themeFor(AppColors.light);

  /// Status and navigation bar icons, which the system draws over whichever
  /// palette is in force - a transparent app bar gives Material nothing to
  /// infer them from.
  static SystemUiOverlayStyle systemOverlayStyleFor(AppColors c) {
    final icons = c.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: c.backgroundPrimary.invisible,
      statusBarIconBrightness: icons,
      statusBarBrightness: c.brightness,
      systemNavigationBarColor: c.backgroundPrimary,
      systemNavigationBarIconBrightness: icons,
    );
  }

  /// [wideLayout] drives sizing that should follow the same desktop-or-
  /// landscape rule as the rest of the shell (see [isWideLayout]). Left
  /// null - falling back to [isDesktopPlatform] alone - for the callers
  /// that build a `ThemeData` with no `BuildContext` in hand, so it stays
  /// what it always was until they have a size to pass.
  ///
  /// Tap feedback (splash, highlight, hover, focus) is tinted with the
  /// accent colour on both palettes, rather than Material's grey/white
  /// defaults, so the same tap reads as the same press on either theme.
  ///
  /// A modal sheet is width-capped on a wide layout: Flutter centers one
  /// narrower than the screen on its own, which a desktop window needs, since
  /// full width there would read as a form stretched edge to edge. It has no
  /// border side, unlike the other surfaces over a scrim, because it already
  /// announces its edge with the grab handle `showAppSheet` draws.
  static ThemeData themeFor(AppColors c, {bool? wideLayout}) {
    final wide = wideLayout ?? isDesktopPlatform;
    return ThemeData(
      brightness: c.brightness,
      useMaterial3: true,
      extensions: [c],
      scaffoldBackgroundColor: c.backgroundPrimary,
      colorScheme: ColorScheme(
        brightness: c.brightness,
        primary: c.primary,
        onPrimary: c.onPrimary,
        secondary: c.primary,
        onSecondary: c.onPrimary,
        error: c.error,
        onError: c.onPrimary,
        surface: c.surfaceCard,
        onSurface: c.textPrimary,
        surfaceContainerLowest: c.backgroundPrimary,
        surfaceContainerLow: c.surfaceCard,
        surfaceContainer: c.surfaceElevated,
        surfaceContainerHigh: c.surfaceOffset,
        outlineVariant: c.surfaceDivider,
      ),
      dividerTheme: DividerThemeData(color: c.surfaceDivider),
      canvasColor: c.backgroundPrimary,
      splashColor: c.primary.withValues(alpha: 0.10),
      highlightColor: c.primary.withValues(alpha: 0.06),
      hoverColor: c.primary.withValues(alpha: 0.05),
      focusColor: c.primary.withValues(alpha: 0.10),
      textTheme: textThemeFor(c),
      appBarTheme: AppBarTheme(
        backgroundColor: c.backgroundPrimary.invisible,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: c.backgroundPrimary.invisible,
        shape: Border(bottom: BorderSide(color: c.surfaceBorder, width: 1)),
        systemOverlayStyle: systemOverlayStyleFor(c),
        titleTextStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: c.textPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: c.surfaceBorderStrong),
        ),
        contentTextStyle: TextStyle(fontFamily: uiFamily, color: c.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: c.textSecondary,
        ),
        hintStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 14,
          color: c.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: c.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: c.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: c.primary, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: c.surfaceBorderStrong),
        ),
        titleTextStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: c.surfaceElevated.invisible,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: c.surfaceBorderStrong),
        ),
        textStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceElevated),
          surfaceTintColor: WidgetStatePropertyAll(c.surfaceElevated.invisible),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(
            BorderSide(color: c.surfaceBorderStrong, width: 1.2),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceElevated),
          surfaceTintColor: WidgetStatePropertyAll(c.surfaceElevated.invisible),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(
            BorderSide(color: c.surfaceBorderStrong, width: 1.2),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(0, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily: uiFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.surfaceBorder),
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily: uiFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXs),
          ),
          textStyle: const TextStyle(
            fontFamily: uiFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily: uiFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceCard,
        modalBackgroundColor: c.surfaceCard,
        surfaceTintColor: c.surfaceCard.invisible,
        constraints: wide ? const BoxConstraints(maxWidth: 560) : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : c.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primaryHighlight
              : c.surfaceOffset,
        ),
        trackOutlineColor: WidgetStatePropertyAll(c.surfaceBorder),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceCard,
        indicatorColor: c.primary.withValues(alpha: 0.15),
        surfaceTintColor: c.surfaceCard.invisible,
        elevation: 0,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.primary
                : c.textTertiary,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontFamily: uiFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? c.primary
                : c.textTertiary,
          );
        }),
      ),
      cardColor: c.surfaceCard,
      dividerColor: c.surfaceDivider,
    );
  }
}

import 'package:flutter/material.dart';

import 'terminal_color_scheme.dart';

const TerminalColorScheme terminalSchemeDefault = TerminalColorScheme(
  background: Color(0xFF070A0D),
  foreground: kTerminalChromeForeground,
  cursor: kTerminalChromeCursor,
  selection: Color(0x44888888),
  black: Color(0xFF0C1115),
  red: Color(0xFFFF7373),
  green: Color(0xFF61D99A),
  yellow: Color(0xFFF4BD50),
  blue: Color(0xFF5B8DEF),
  magenta: Color(0xFF9B8EC4),
  cyan: Color(0xFF5BA8B5),
  white: Color(0xFFAEB9C0),
  brightBlack: Color(0xFF4B5563),
  brightRed: Color(0xFFFF9C9C),
  brightGreen: Color(0xFF7FE7B4),
  brightYellow: Color(0xFFFBBF24),
  brightBlue: Color(0xFF7BA8F7),
  brightMagenta: Color(0xFFB5A8D9),
  brightCyan: Color(0xFF7BC8D4),
  brightWhite: Color(0xFFF9FAFB),
  uiBorder: Color(0xFF2B3943),
  uiSurface: Color(0xFF0B1014),
  uiActiveBorder: Color(0xFF2A3A45),
);

/// A light terminal scheme, for pairing with the light interface theme - the
/// terminal's own scheme stays a separate choice either way.
const TerminalColorScheme terminalSchemeLight = TerminalColorScheme(
  background: Color(0xFFFFFFFF),
  foreground: Color(0xFF24292F),
  cursor: Color(0xFF0B6BD6),
  selection: Color(0x330B6BD6),
  black: Color(0xFF24292F),
  red: Color(0xFFCF222E),
  green: Color(0xFF167D34),
  yellow: Color(0xFF915930),
  blue: Color(0xFF0969DA),
  magenta: Color(0xFF8250DF),
  cyan: Color(0xFF1B7C83),
  white: Color(0xFF6E7781),
  brightBlack: Color(0xFF5C6979),
  brightRed: Color(0xFFE3525C),
  brightGreen: Color(0xFF1B9A40),
  brightYellow: Color(0xFFB46E3B),
  brightBlue: Color(0xFF2685F6),
  brightMagenta: Color(0xFF9B72E5),
  brightCyan: Color(0xFF2198A1),
  brightWhite: Color(0xFF89919B),
  uiBorder: Color(0xFFD3DBE3),
  uiSurface: Color(0xFFF5F7FA),
  uiActiveBorder: Color(0xFFB6C2CE),
);

const TerminalColorScheme terminalSchemeTokyoNight = TerminalColorScheme(
  background: kTerminalChromeBackground,
  foreground: kTerminalChromeForeground,
  cursor: kTerminalChromeCursor,
  selection: Color(0x665B638A),
  black: Color(0xFF15161E),
  red: Color(0xFFF7768E),
  green: Color(0xFF9ECE6A),
  yellow: Color(0xFFE0AF68),
  blue: Color(0xFF7AA2F7),
  magenta: Color(0xFFBB9AF7),
  cyan: Color(0xFF7DCFFF),
  white: Color(0xFFC0CAF5),
  brightBlack: Color(0xFF414868),
  brightRed: Color(0xFFFF7A93),
  brightGreen: Color(0xFFB9F27C),
  brightYellow: Color(0xFFFFC777),
  brightBlue: Color(0xFF8EB0FF),
  brightMagenta: Color(0xFFC7A9FF),
  brightCyan: Color(0xFF92D6FF),
  brightWhite: Color(0xFFD5D6DB),
  uiBorder: Color(0xFF414868),
  uiSurface: Color(0xFF15161E),
  uiActiveBorder: Color(0xFF555D7E),
);

const TerminalColorScheme terminalSchemeDracula = TerminalColorScheme(
  background: Color(0xFF282A36),
  foreground: Color(0xFFF8F8F2),
  cursor: Color(0xFFF8F8F2),
  selection: Color(0x665A5F78),
  black: Color(0xFF21222C),
  red: Color(0xFFFF5555),
  green: Color(0xFF50FA7B),
  yellow: Color(0xFFF1FA8C),
  blue: Color(0xFFBD93F9),
  magenta: Color(0xFFFF79C6),
  cyan: Color(0xFF8BE9FD),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF6272A4),
  brightRed: Color(0xFFFF6E6E),
  brightGreen: Color(0xFF69FF94),
  brightYellow: Color(0xFFFFFFA5),
  brightBlue: Color(0xFFD6ACFF),
  brightMagenta: Color(0xFFFF92DF),
  brightCyan: Color(0xFFA4FFFF),
  brightWhite: Color(0xFFFFFFFF),
  uiBorder: Color(0xFF6272A4),
  uiSurface: Color(0xFF21222C),
  uiActiveBorder: Color(0xFF7A88B4),
);

const TerminalColorScheme terminalSchemeNord = TerminalColorScheme(
  background: Color(0xFF2E3440),
  foreground: Color(0xFFD8DEE9),
  cursor: Color(0xFF88C0D0),
  selection: Color(0x6681A1C1),
  black: Color(0xFF3B4252),
  red: Color(0xFFBF616A),
  green: Color(0xFFA3BE8C),
  yellow: Color(0xFFEBCB8B),
  blue: Color(0xFF81A1C1),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF88C0D0),
  white: Color(0xFFE5E9F0),
  brightBlack: Color(0xFF4C566A),
  brightRed: Color(0xFFBF616A),
  brightGreen: Color(0xFFA3BE8C),
  brightYellow: Color(0xFFEBCB8B),
  brightBlue: Color(0xFF81A1C1),
  brightMagenta: Color(0xFFB48EAD),
  brightCyan: Color(0xFF8FBCBB),
  brightWhite: Color(0xFFECEFF4),
  uiBorder: Color(0xFF4C566A),
  uiSurface: Color(0xFF3B4252),
  uiActiveBorder: Color(0xFF616C82),
);

const TerminalColorScheme terminalSchemeGruvbox = TerminalColorScheme(
  background: Color(0xFF282828),
  foreground: Color(0xFFEBDBB2),
  cursor: Color(0xFFD4BE98),
  selection: Color(0x66504945),
  black: Color(0xFF1D2021),
  red: Color(0xFFCC241D),
  green: Color(0xFF98971A),
  yellow: Color(0xFFD79921),
  blue: Color(0xFF458588),
  magenta: Color(0xFFB16286),
  cyan: Color(0xFF689D6A),
  white: Color(0xFFA89984),
  brightBlack: Color(0xFF928374),
  brightRed: Color(0xFFFB4934),
  brightGreen: Color(0xFFB8BB26),
  brightYellow: Color(0xFFFABD2F),
  brightBlue: Color(0xFF83A598),
  brightMagenta: Color(0xFFD3869B),
  brightCyan: Color(0xFF8EC07C),
  brightWhite: Color(0xFFEBDBB2),
  uiBorder: Color(0xFF928374),
  uiSurface: Color(0xFF1D2021),
  uiActiveBorder: Color(0xFFAB9E90),
);

const TerminalColorScheme terminalSchemeOneDark = TerminalColorScheme(
  background: Color(0xFF282C34),
  foreground: Color(0xFFABB2BF),
  cursor: Color(0xFF528BFF),
  selection: Color(0x66528BFF),
  black: Color(0xFF282C34),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFABB2BF),
  brightBlack: Color(0xFF545862),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  uiBorder: Color(0xFF545862),
  uiSurface: Color(0xFF282C34),
  uiActiveBorder: Color(0xFF6B7080),
);

const TerminalColorScheme terminalSchemeCatppuccin = TerminalColorScheme(
  background: Color(0xFF1E1E2E),
  foreground: Color(0xFFCDD6F4),
  cursor: Color(0xFFF5C2E7),
  selection: Color(0x6689B4FA),
  black: Color(0xFF45475A),
  red: Color(0xFFF38BA8),
  green: Color(0xFFA6E3A1),
  yellow: Color(0xFFF9E2AF),
  blue: Color(0xFF89B4FA),
  magenta: Color(0xFFF5C2E7),
  cyan: Color(0xFF94E2D5),
  white: Color(0xFFBAC2DE),
  brightBlack: Color(0xFF585B70),
  brightRed: Color(0xFFF38BA8),
  brightGreen: Color(0xFFA6E3A1),
  brightYellow: Color(0xFFF9E2AF),
  brightBlue: Color(0xFF89B4FA),
  brightMagenta: Color(0xFFF5C2E7),
  brightCyan: Color(0xFF94E2D5),
  brightWhite: Color(0xFFA6ADC8),
  uiBorder: Color(0xFF585B70),
  uiSurface: Color(0xFF45475A),
  uiActiveBorder: Color(0xFF6E718C),
);

const TerminalColorScheme terminalSchemeMatrix = TerminalColorScheme(
  background: Color(0xFF041304),
  foreground: Color(0xFF9DFF9D),
  cursor: Color(0xFF00FF41),
  selection: Color(0x6633FF66),
  black: Color(0xFF001A00),
  red: Color(0xFF66FF66),
  green: Color(0xFF00FF41),
  yellow: Color(0xFF8CFF8C),
  blue: Color(0xFF52FF52),
  magenta: Color(0xFF7DFF7D),
  cyan: Color(0xFF5BFF5B),
  white: Color(0xFFB8FFB8),
  brightBlack: Color(0xFF2A662A),
  brightRed: Color(0xFF8CFF8C),
  brightGreen: Color(0xFF33FF66),
  brightYellow: Color(0xFFA8FFA8),
  brightBlue: Color(0xFF75FF75),
  brightMagenta: Color(0xFF9AFF9A),
  brightCyan: Color(0xFF86FF86),
  brightWhite: Color(0xFFD6FFD6),
  uiBorder: Color(0xFF2A662A),
  uiSurface: Color(0xFF001A00),
  uiActiveBorder: Color(0xFF3D8A3D),
);

/// Tokyo Night's own day variant.
const TerminalColorScheme terminalSchemeTokyoNightDay = TerminalColorScheme(
  background: Color(0xFFE1E2E7),
  foreground: Color(0xFF3760BF),
  cursor: Color(0xFF3760BF),
  selection: Color(0x4499A7DF),
  black: Color(0xFF313134),
  red: Color(0xFFF52A65),
  green: Color(0xFF587539),
  yellow: Color(0xFF8C6C3E),
  blue: Color(0xFF2E7DE9),
  magenta: Color(0xFF9854F1),
  cyan: Color(0xFF007197),
  white: Color(0xFF6172B0),
  brightBlack: Color(0xFF64646B),
  brightRed: Color(0xFFF74B7D),
  brightGreen: Color(0xFF6D9046),
  brightYellow: Color(0xFFAC854C),
  brightBlue: Color(0xFF478CEC),
  brightMagenta: Color(0xFFA86FF3),
  brightCyan: Color(0xFF008CBB),
  brightWhite: Color(0xFF808DBF),
  uiBorder: Color(0xFFC4C8DA),
  uiSurface: Color(0xFFD7D9E3),
  uiActiveBorder: Color(0xFFA1A6C5),
);

/// Alucard - Dracula's official light counterpart.
const TerminalColorScheme terminalSchemeAlucard = TerminalColorScheme(
  background: Color(0xFFFFFBEB),
  foreground: Color(0xFF1F1F1F),
  cursor: Color(0xFF644AC9),
  selection: Color(0x44CFCFDE),
  black: Color(0xFF1F1F1F),
  red: Color(0xFFCB3A2A),
  green: Color(0xFF14710A),
  yellow: Color(0xFF846E15),
  blue: Color(0xFF6F56CD),
  magenta: Color(0xFFCD1961),
  cyan: Color(0xFF036A96),
  white: Color(0xFF6C664B),
  brightBlack: Color(0xFF656565),
  brightRed: Color(0xFFDC6356),
  brightGreen: Color(0xFF198D0C),
  brightYellow: Color(0xFFA2871A),
  brightBlue: Color(0xFF8974D6),
  brightMagenta: Color(0xFFE84385),
  brightCyan: Color(0xFF0484BB),
  brightWhite: Color(0xFF867F5D),
  uiBorder: Color(0xFFDCD7C0),
  uiSurface: Color(0xFFF5F0DE),
  uiActiveBorder: Color(0xFFBEB79A),
);

const TerminalColorScheme terminalSchemeGruvboxLight = TerminalColorScheme(
  background: Color(0xFFFBF1C7),
  foreground: Color(0xFF3C3836),
  cursor: Color(0xFF3C3836),
  selection: Color(0x44D5C4A1),
  black: Color(0xFF403933),
  red: Color(0xFFCC241D),
  green: Color(0xFF98971A),
  yellow: Color(0xFFD79921),
  blue: Color(0xFF458588),
  magenta: Color(0xFFB16286),
  cyan: Color(0xFF689D6A),
  white: Color(0xFF7C6F64),
  brightBlack: Color(0xFF796C60),
  brightRed: Color(0xFFE54D47),
  brightGreen: Color(0xFF9C9B1B),
  brightYellow: Color(0xFFE2AA40),
  brightBlue: Color(0xFF54A2A5),
  brightMagenta: Color(0xFFC284A0),
  brightCyan: Color(0xFF70A272),
  brightWhite: Color(0xFF96897D),
  uiBorder: Color(0xFFE0D5AF),
  uiSurface: Color(0xFFF2E5BC),
  uiActiveBorder: Color(0xFFBDB292),
);

const TerminalColorScheme terminalSchemeOneLight = TerminalColorScheme(
  background: Color(0xFFFAFAFA),
  foreground: Color(0xFF383A42),
  cursor: Color(0xFF526FFF),
  selection: Color(0x33526FFF),
  black: Color(0xFF383A42),
  red: Color(0xFFE45649),
  green: Color(0xFF50A14F),
  yellow: Color(0xFFC18401),
  blue: Color(0xFF4078F2),
  magenta: Color(0xFFA626A4),
  cyan: Color(0xFF0184BC),
  white: Color(0xFF8E8F96),
  brightBlack: Color(0xFF6A6E7D),
  brightRed: Color(0xFFEA7E74),
  brightGreen: Color(0xFF5CAF5B),
  brightYellow: Color(0xFFD29001),
  brightBlue: Color(0xFF6C97F5),
  brightMagenta: Color(0xFFCE2FCC),
  brightCyan: Color(0xFF01A0E4),
  brightWhite: Color(0xFFA2A3A9),
  uiBorder: Color(0xFFE1E1E3),
  uiSurface: Color(0xFFF0F0F1),
  uiActiveBorder: Color(0xFFC2C2C6),
);

/// Catppuccin's light flavour.
const TerminalColorScheme terminalSchemeCatppuccinLatte = TerminalColorScheme(
  background: Color(0xFFEFF1F5),
  foreground: Color(0xFF4C4F69),
  cursor: Color(0xFFDC8A78),
  selection: Color(0x441E66F5),
  black: Color(0xFF383A48),
  red: Color(0xFFD20F39),
  green: Color(0xFF40A02B),
  yellow: Color(0xFFDF8E1D),
  blue: Color(0xFF1E66F5),
  magenta: Color(0xFFEA76CB),
  cyan: Color(0xFF179299),
  white: Color(0xFF8C8FA1),
  brightBlack: Color(0xFF6A6D88),
  brightRed: Color(0xFFF13A62),
  brightGreen: Color(0xFF44AB2E),
  brightYellow: Color(0xFFE6A03E),
  brightBlue: Color(0xFF4E87F7),
  brightMagenta: Color(0xFFEE8DD4),
  brightCyan: Color(0xFF1AA6AE),
  brightWhite: Color(0xFF9A9CAC),
  uiBorder: Color(0xFFDCE0E8),
  uiSurface: Color(0xFFE6E9EF),
  uiActiveBorder: Color(0xFFBCC0CC),
);

TerminalColorScheme terminalSchemeForId(String schemeId) {
  switch (schemeId) {
    case 'tokyo-night':
      return terminalSchemeTokyoNight;
    case 'dracula':
      return terminalSchemeDracula;
    case 'nord':
      return terminalSchemeNord;
    case 'gruvbox':
      return terminalSchemeGruvbox;
    case 'one-dark':
      return terminalSchemeOneDark;
    case 'catppuccin':
      return terminalSchemeCatppuccin;
    case 'matrix':
      return terminalSchemeMatrix;
    case 'light':
      return terminalSchemeLight;
    case 'tokyo-night-day':
      return terminalSchemeTokyoNightDay;
    case 'alucard':
      return terminalSchemeAlucard;
    case 'gruvbox-light':
      return terminalSchemeGruvboxLight;
    case 'one-light':
      return terminalSchemeOneLight;
    case 'catppuccin-latte':
      return terminalSchemeCatppuccinLatte;
    case 'default':
    default:
      return terminalSchemeDefault;
  }
}

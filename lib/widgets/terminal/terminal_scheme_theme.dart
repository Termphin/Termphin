import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings/terminal_settings.dart';
import '../../theme/theme.dart';

/// The scheme the terminal chrome is painted in, or null until it is read.
///
/// Global because the chrome is not one subtree: sheets, dialogs, overlays and
/// pushed pages all render somewhere else in the tree, and every one of them
/// has to reach the same answer.
final ValueNotifier<TerminalColorScheme?> terminalChromeScheme = ValueNotifier(
  null,
);

bool _listening = false;

/// Starts tracking the setting, once per process. Safe to call from anywhere
/// that is about to show terminal chrome.
void ensureTerminalChromeScheme() {
  if (_listening) return;
  _listening = true;
  terminalSettings.scheme.addListener(_reload);
  _reload();
}

void _reload() {
  terminalChromeScheme.value = AppTheme.terminalSchemeForId(
    terminalSettings.scheme.value,
  );
}

@visibleForTesting
void resetTerminalChromeScheme() {
  if (_listening) terminalSettings.scheme.removeListener(_reload);
  _listening = false;
  terminalChromeScheme.value = null;
}

/// Repaints everything below it in the colours of the selected terminal
/// scheme - the tab strip, the key toolbar, the action dock, the connecting
/// screen, the SFTP browser and everything they open.
///
/// Wrapping rather than colouring each piece is what makes that work without
/// touching any of them: they already read their colours off the context, so
/// swapping the theme above them is the whole change.
///
/// Where to put it: outside the widget whose colours should change - a
/// `Theme` a widget returns sits below its own `State.context`, so the widget
/// itself would keep reading the palette it was built under. `showDialog` and
/// `showModalBottomSheet` carry the ambient theme into the root navigator on
/// their own ([InheritedTheme.capture]), so anything opened that way from
/// inside the terminal is already covered. `showGeneralDialog`, a raw
/// [OverlayEntry] and a pushed [MaterialPageRoute] are not - those need this
/// around their content.
class TerminalSchemeTheme extends StatefulWidget {
  const TerminalSchemeTheme({super.key, required this.child});

  final Widget child;

  @override
  State<TerminalSchemeTheme> createState() => _TerminalSchemeThemeState();
}

/// Until the setting is read, the app theme is a better guess than a
/// default scheme that may not be the one about to load. Once a scheme is
/// loaded, the system bars are repainted to sit over this subtree's
/// colours, not the app's - a light scheme under a dark app would
/// otherwise leave white icons on white.
class _TerminalSchemeThemeState extends State<TerminalSchemeTheme> {
  TerminalColorScheme? _builtFor;
  late AppColors _colors;
  late ThemeData _theme;

  void _buildFor(TerminalColorScheme scheme) {
    if (identical(scheme, _builtFor)) return;
    _builtFor = scheme;
    _colors = AppColors.fromTerminalScheme(scheme);
    _theme = AppTheme.themeFor(_colors);
  }

  @override
  void initState() {
    super.initState();
    ensureTerminalChromeScheme();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TerminalColorScheme?>(
      valueListenable: terminalChromeScheme,
      builder: (context, scheme, child) {
        if (scheme == null) return child!;
        _buildFor(scheme);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemOverlayStyleFor(_colors),
          child: Theme(data: _theme, child: child!),
        );
      },
      child: widget.child,
    );
  }
}

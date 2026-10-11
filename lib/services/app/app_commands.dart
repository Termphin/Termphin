import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:terminal_view/terminal_view.dart' show TerminalView;

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';

/// Everything the app does on a keyboard shortcut or from the title bar's
/// menus. One list, so the shortcut, the menu entry and the shortcuts sheet
/// can never disagree about what a command is called or which keys run it.
enum AppCommand {
  globalSearch,
  newMachine,
  newSession,
  closeTab,
  nextTab,
  previousTab,
  selectTab,
  findInTerminal,
  uploadFile,
  zoomIn,
  zoomOut,
  zoomReset,
  openSettings,
  toggleSidebar,
  showShortcuts,
  openManual,
  quit,
}

/// Runs [AppCommand]s for whoever registered to handle them, and owns the
/// keyboard shortcuts that trigger them on a desktop.
///
/// The shortcuts are read off [HardwareKeyboard] before focus sees a key, not
/// through a `Shortcuts` widget: the terminal takes every key it is given and
/// sends it down the wire, so a binding that waited for the event to bubble
/// up from it would never fire while a session has focus - which is when
/// most of them are wanted. That is also why, off macOS, they are all on
/// Ctrl+Shift: a shell owns plain Ctrl.
class AppCommands {
  AppCommands._();

  static final instance = AppCommands._();

  final _handlers = <AppCommand, List<bool Function(int? argument)>>{};
  bool _installed = false;

  /// Dialogs and sheets on screen over the app. A shortcut aimed at what is
  /// behind them - a new tab under a half-filled form - does nothing.
  int _modalDepth = 0;

  /// Registers [handler] for [command]. The last one registered is asked
  /// first, and one that returns false passes the command down. Returns the
  /// call that unregisters it.
  VoidCallback register(
    AppCommand command,
    bool Function(int? argument) handler,
  ) {
    final list = _handlers.putIfAbsent(command, () => []);
    list.add(handler);
    return () => list.remove(handler);
  }

  final _escapeHandlers = <bool Function()>[];

  /// Registers what Esc does on a screen with nothing of Flutter's own to
  /// close - clearing a selection, typically. Returns whether it did
  /// anything; one that returns false hands Esc on. Never asked while the
  /// terminal has the keyboard: Esc there is the shell's, and vim's.
  VoidCallback registerEscape(bool Function() handler) {
    _escapeHandlers.add(handler);
    return () => _escapeHandlers.remove(handler);
  }

  bool _runEscape() {
    if (_terminalHasFocus()) return false;
    for (final handler in _escapeHandlers.reversed.toList()) {
      if (handler()) return true;
    }
    return false;
  }

  static bool _terminalHasFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.findAncestorWidgetOfExactType<TerminalView>() != null;
  }

  /// The command the keyboard ran last, and when - see [runFromMenu].
  AppCommand? _lastKeyed;
  DateTime? _lastKeyedAt;

  /// Runs [command] for a menu entry. A Mac's menu bar answers its own key
  /// equivalents, and whether the same keystroke also reaches the keyboard
  /// handler is the engine's business; a command the keyboard ran a moment
  /// ago is that keystroke arriving twice, and runs once.
  bool runFromMenu(AppCommand command) {
    final at = _lastKeyedAt;
    if (_lastKeyed == command &&
        at != null &&
        DateTime.now().difference(at) < const Duration(milliseconds: 250)) {
      return true;
    }
    return run(command);
  }

  /// Runs [command], returning whether anything did.
  bool run(AppCommand command, {int? argument}) {
    final list = _handlers[command];
    if (list == null) return false;
    for (final handler in list.reversed.toList()) {
      if (handler(argument)) return true;
    }
    return false;
  }

  /// Listens for the shortcuts. Desktop only: a phone's hardware keyboard is
  /// the terminal's, and none of these were ever promised there.
  void install() {
    if (_installed || !isDesktopPlatform) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @visibleForTesting
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  /// Watches the root navigator for modals, see [_modalDepth].
  late final NavigatorObserver modalObserver = _ModalObserver(this);

  /// Whether [event] is one of the shortcuts - for the terminal, which
  /// would otherwise send it on to the shell as well: the handler above sees
  /// every key, but seeing one does not keep it from the focused widget.
  bool claims(KeyEvent event) {
    if (!_installed) return false;
    final keyboard = HardwareKeyboard.instance;
    for (final command in AppCommand.values) {
      for (final activator in activatorsFor(command)) {
        if (activator.accepts(event, keyboard)) return true;
      }
    }
    return (event is KeyDownEvent || event is KeyRepeatEvent) &&
        _digitKeys.contains(event.logicalKey) &&
        _tabModifierHeld(keyboard);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_modalDepth > 0) return false;
    final keyboard = HardwareKeyboard.instance;
    for (final command in AppCommand.values) {
      if (command == AppCommand.selectTab) continue;
      for (final activator in activatorsFor(command)) {
        if (activator.accepts(event, keyboard)) {
          if (event is KeyRepeatEvent && !_repeats(command)) return false;
          _lastKeyed = command;
          _lastKeyedAt = DateTime.now();
          return run(command);
        }
      }
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        !keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      return _runEscape();
    }
    if (event is KeyDownEvent) {
      final digit = _digitKeys.indexOf(event.logicalKey);
      if (digit >= 0 && _tabModifierHeld(keyboard)) {
        return run(AppCommand.selectTab, argument: digit);
      }
    }
    return false;
  }

  /// The commands a held key repeats: only what is meant to be held down.
  static bool _repeats(AppCommand command) =>
      command == AppCommand.zoomIn ||
      command == AppCommand.zoomOut ||
      command == AppCommand.nextTab ||
      command == AppCommand.previousTab;

  static final _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// Alt+digit off macOS, as in most terminals there; Cmd+digit on a Mac.
  static bool _tabModifierHeld(HardwareKeyboard keyboard) {
    if (isMacOSPlatform) {
      return keyboard.isMetaPressed &&
          !keyboard.isControlPressed &&
          !keyboard.isAltPressed;
    }
    return keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed;
  }

  /// The keys that run [command] on this platform; the first is the one
  /// menus and the shortcuts sheet show.
  ///
  /// Upload is O for open, as a file picker is; Ctrl+Shift+U would be the
  /// mnemonic, but IBus takes it for Unicode input before the app hears it.
  /// Zoom is Ctrl and the zoom keys, with no Shift, as every terminal on
  /// these systems has them - a shell has no use for Ctrl+= or Ctrl+0.
  static List<SingleActivator> activatorsFor(AppCommand command) {
    final mac = isMacOSPlatform;
    SingleActivator primary(LogicalKeyboardKey key, {bool shift = false}) => mac
        ? SingleActivator(key, meta: true, shift: shift)
        : SingleActivator(key, control: true, shift: true);
    return switch (command) {
      AppCommand.globalSearch => [primary(LogicalKeyboardKey.keyK)],
      AppCommand.newMachine => [primary(LogicalKeyboardKey.keyN)],
      AppCommand.newSession => [primary(LogicalKeyboardKey.keyT)],
      AppCommand.closeTab => [primary(LogicalKeyboardKey.keyW)],
      AppCommand.nextTab => [
        const SingleActivator(LogicalKeyboardKey.tab, control: true),
        if (!mac)
          const SingleActivator(LogicalKeyboardKey.pageDown, control: true),
        if (mac)
          const SingleActivator(
            LogicalKeyboardKey.bracketRight,
            meta: true,
            shift: true,
          ),
      ],
      AppCommand.previousTab => [
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ),
        if (!mac)
          const SingleActivator(LogicalKeyboardKey.pageUp, control: true),
        if (mac)
          const SingleActivator(
            LogicalKeyboardKey.bracketLeft,
            meta: true,
            shift: true,
          ),
      ],
      AppCommand.selectTab => const [],
      AppCommand.findInTerminal => [primary(LogicalKeyboardKey.keyF)],
      AppCommand.uploadFile => [primary(LogicalKeyboardKey.keyO)],
      AppCommand.zoomIn => [
        SingleActivator(LogicalKeyboardKey.equal, control: !mac, meta: mac),
        SingleActivator(
          LogicalKeyboardKey.equal,
          control: !mac,
          meta: mac,
          shift: true,
        ),
        SingleActivator(LogicalKeyboardKey.numpadAdd, control: !mac, meta: mac),
      ],
      AppCommand.zoomOut => [
        SingleActivator(LogicalKeyboardKey.minus, control: !mac, meta: mac),
        SingleActivator(
          LogicalKeyboardKey.numpadSubtract,
          control: !mac,
          meta: mac,
        ),
      ],
      AppCommand.zoomReset => [
        SingleActivator(LogicalKeyboardKey.digit0, control: !mac, meta: mac),
      ],
      AppCommand.openSettings => [
        mac
            ? const SingleActivator(LogicalKeyboardKey.comma, meta: true)
            : const SingleActivator(
                LogicalKeyboardKey.comma,
                control: true,
                shift: true,
              ),
      ],
      AppCommand.toggleSidebar => [primary(LogicalKeyboardKey.keyB)],
      AppCommand.showShortcuts => [
        mac
            ? const SingleActivator(LogicalKeyboardKey.slash, meta: true)
            : const SingleActivator(
                LogicalKeyboardKey.slash,
                control: true,
                shift: true,
              ),
      ],
      AppCommand.openManual => [const SingleActivator(LogicalKeyboardKey.f1)],
      AppCommand.quit => [primary(LogicalKeyboardKey.keyQ)],
    };
  }

  /// The shortcut as a menu prints it: "Ctrl+Shift+T", or "⌘T" on a Mac.
  static String? shortcutLabel(AppCommand command) {
    if (command == AppCommand.selectTab) {
      return isMacOSPlatform ? '⌘1…9' : 'Alt+1…9';
    }
    final activators = activatorsFor(command);
    if (activators.isEmpty) return null;
    return describeActivator(activators.first);
  }

  static String describeActivator(SingleActivator activator) {
    final key = _keyName(activator.trigger);
    if (isMacOSPlatform) {
      return [
        if (activator.control) '⌃',
        if (activator.alt) '⌥',
        if (activator.shift) '⇧',
        if (activator.meta) '⌘',
        key,
      ].join();
    }
    return [
      if (activator.control) 'Ctrl',
      if (activator.alt) 'Alt',
      if (activator.shift) 'Shift',
      if (activator.meta) 'Win',
      key,
    ].join('+');
  }

  static String _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.equal) return '=';
    if (key == LogicalKeyboardKey.minus) return '−';
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.bracketLeft) return '[';
    if (key == LogicalKeyboardKey.bracketRight) return ']';
    return key.keyLabel.toUpperCase();
  }

  static String label(Translations t, AppCommand command) => switch (command) {
    AppCommand.globalSearch => t.commands.globalSearch,
    AppCommand.newMachine => t.commands.newMachine,
    AppCommand.newSession => t.commands.newSession,
    AppCommand.closeTab => t.commands.closeTab,
    AppCommand.nextTab => t.commands.nextTab,
    AppCommand.previousTab => t.commands.previousTab,
    AppCommand.selectTab => t.commands.selectTab,
    AppCommand.findInTerminal => t.commands.findInTerminal,
    AppCommand.uploadFile => t.commands.uploadFile,
    AppCommand.zoomIn => t.commands.zoomIn,
    AppCommand.zoomOut => t.commands.zoomOut,
    AppCommand.zoomReset => t.commands.zoomReset,
    AppCommand.openSettings => t.commands.openSettings,
    AppCommand.toggleSidebar => t.commands.toggleSidebar,
    AppCommand.showShortcuts => t.commands.showShortcuts,
    AppCommand.openManual => t.commands.openManual,
    AppCommand.quit => t.commands.quit,
  };
}

class _ModalObserver extends NavigatorObserver {
  _ModalObserver(this.commands);

  final AppCommands commands;

  bool _isModal(Route<dynamic> route) => route is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) commands._modalDepth++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) commands._modalDepth--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) commands._modalDepth--;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null && _isModal(oldRoute)) commands._modalDepth--;
    if (newRoute != null && _isModal(newRoute)) commands._modalDepth++;
  }
}

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../utils/platform_info.dart';

/// The keys the file browser answers while it has the keyboard on a desktop.
///
/// One list, read by the browser's key handler, its menu in the title bar,
/// its tooltips and the shortcuts sheet, so none of them can name a key the
/// browser does not take. They are the browser's own and not `AppCommand`s:
/// those are heard everywhere, and F2 or Delete must mean nothing in a
/// terminal.
///
/// Plain keys and function keys where a file manager has them. The ones on
/// Ctrl are free because the app's own shortcuts are all on Ctrl+Shift off a
/// Mac; on a Mac, where they share Cmd, the letters are picked around the
/// app's and the system's (Cmd+H hides the app, so hidden files are
/// Cmd+Shift+. as in Finder).
abstract final class SftpShortcuts {
  static bool get _mac => isMacOSPlatform;

  static SingleActivator _primary(LogicalKeyboardKey key) =>
      SingleActivator(key, control: !_mac, meta: _mac);

  static const open = SingleActivator(LogicalKeyboardKey.enter);
  static const parentFolder = SingleActivator(LogicalKeyboardKey.backspace);
  static const back = SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true);
  static const refresh = SingleActivator(LogicalKeyboardKey.f5);
  static const newFolder = SingleActivator(LogicalKeyboardKey.f7);
  static const newFile = SingleActivator(LogicalKeyboardKey.f7, shift: true);
  static const rename = SingleActivator(LogicalKeyboardKey.f2);
  static const delete = SingleActivator(LogicalKeyboardKey.delete);
  static const copyTo = SingleActivator(LogicalKeyboardKey.f6, shift: true);
  static const moveTo = SingleActivator(LogicalKeyboardKey.f6);

  /// In the copy and move picker: take the folder being shown, whatever
  /// row the cursor is on.
  static SingleActivator get chooseHere => _primary(LogicalKeyboardKey.enter);

  static SingleActivator get toggleHidden => _mac
      ? const SingleActivator(
          LogicalKeyboardKey.period,
          meta: true,
          shift: true,
        )
      : const SingleActivator(LogicalKeyboardKey.keyH, control: true);

  static SingleActivator get selectAll => _primary(LogicalKeyboardKey.keyA);
  static SingleActivator get download => _primary(LogicalKeyboardKey.keyD);
}

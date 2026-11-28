import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../utils/platform_info.dart';

/// The keys a desktop user expects on anything that edits and saves: Ctrl+S,
/// or Cmd+S on a Mac, runs [onSave], and Escape runs [onClose].
///
/// They act for whatever has focus inside [child], so a text field or the
/// code editor keeps every key it handles itself - Escape reaches [onClose]
/// only once nothing deeper, such as an open find bar, took it. A null
/// [onSave] leaves Ctrl+S alone, the same as a disabled Save button.
///
/// On a desktop the keys work the moment the form opens: it takes the focus
/// itself, which would otherwise stay on the page beneath until the user
/// clicked into a field.
class SaveShortcuts extends StatelessWidget {
  const SaveShortcuts({
    super.key,
    required this.onSave,
    this.onClose,
    required this.child,
  });

  final VoidCallback? onSave;
  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyS,
          control: !isMacOSPlatform,
          meta: isMacOSPlatform,
        ): ?onSave,
        const SingleActivator(LogicalKeyboardKey.escape): ?onClose,
      },
      child: Focus(
        autofocus: isDesktopPlatform,
        skipTraversal: true,
        child: child,
      ),
    );
  }
}

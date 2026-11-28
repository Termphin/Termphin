import 'dart:async';

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
/// clicked into a field. It also takes focus back if a nested dialog closes
/// and focus falls back onto the route's bare scope node.
class SaveShortcuts extends StatefulWidget {
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
  State<SaveShortcuts> createState() => _SaveShortcutsState();
}

class _SaveShortcutsState extends State<SaveShortcuts> {
  final FocusNode _focusNode = FocusNode(skipTraversal: true);
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!isDesktopPlatform || !mounted || _restoreScheduled) return;
    if (_focusNode.hasFocus) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    _restoreScheduled = true;
    scheduleMicrotask(() {
      _restoreScheduled = false;
      if (!mounted || _focusNode.hasFocus) return;
      final currentRoute = ModalRoute.of(context);
      if (currentRoute == null || !currentRoute.isCurrent) return;
      final currentPrimary = FocusManager.instance.primaryFocus;
      if (currentPrimary == null || currentPrimary is FocusScopeNode) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyS,
          control: !isMacOSPlatform,
          meta: isMacOSPlatform,
        ): ?widget.onSave,
        const SingleActivator(LogicalKeyboardKey.escape): ?widget.onClose,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: isDesktopPlatform,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}

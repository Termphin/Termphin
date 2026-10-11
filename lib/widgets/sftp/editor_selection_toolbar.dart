import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart' as re;

/// The menu over a selection in the editor. re_editor draws none of its own -
/// without a controller a selection can be made but not copied - so this is
/// the platform's own toolbar, the one every text field shows, with its
/// labels and look. Select All keeps the menu open rather than dismissing
/// it, since there is still a selection afterwards.
re.SelectionToolbarController editorSelectionToolbar() =>
    re.MobileSelectionToolbarController(
      builder:
          ({
            required context,
            required anchors,
            required controller,
            required onDismiss,
            required onRefresh,
          }) {
            final selected = !controller.selection.isCollapsed;
            ContextMenuButtonItem item(
              ContextMenuButtonType type,
              VoidCallback action, {
              bool keepOpen = false,
            }) => ContextMenuButtonItem(
              type: type,
              onPressed: () {
                action();
                keepOpen ? onRefresh() : onDismiss();
              },
            );
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: anchors,
              buttonItems: [
                if (selected) item(ContextMenuButtonType.cut, controller.cut),
                if (selected) item(ContextMenuButtonType.copy, controller.copy),
                item(ContextMenuButtonType.paste, controller.paste),
                if (!controller.isAllSelected)
                  item(
                    ContextMenuButtonType.selectAll,
                    controller.selectAll,
                    keepOpen: true,
                  ),
              ],
            );
          },
    );

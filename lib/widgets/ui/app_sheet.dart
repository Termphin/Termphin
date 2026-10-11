import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'sheet_handle.dart';

/// The one way to open a bottom sheet.
///
/// Every sheet used to pass its own `shape` - a rounded top identical to the
/// theme's - and then either drew a [SheetHandle], asked for Flutter's
/// `showDragHandle`, or had no grab bar at all, so the same gesture was
/// advertised three different ways and twice not at all. Shape and background
/// are left to `bottomSheetTheme`; the handle is drawn here.
///
/// [handle] is for the one case that has to draw its own: a sheet whose
/// content is a `DraggableScrollableSheet` resizes below a bar placed here,
/// so the bar has to live inside that child to move with it.
///
/// [surface] is for a sheet whose colours must change while it is open. The
/// route keeps the theme it was pushed under, background included, so such a
/// sheet paints its own: the route's background goes invisible and the whole
/// sheet, handle and all, is handed to [surface] to wrap in a theme of its
/// choosing and draw the background in.
///
/// Only the handled sheet is inset for the navigation bar here: a sheet
/// that sizes itself with a `DraggableScrollableSheet` measures against
/// the room it is given, and would come up short by the navigation bar's
/// height if this inset it too, so that case is left for the caller to
/// size itself.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool handle = true,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Widget Function(Widget sheet)? surface,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: surface == null
        ? null
        : Theme.of(context).colorScheme.surface.invisible,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (ctx) {
      final child = builder(ctx);
      final Widget sheet = !handle
          ? child
          : SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandle(topPadding: 8),
                  Flexible(child: child),
                ],
              ),
            );
      return surface == null ? sheet : surface(sheet);
    },
  );
}

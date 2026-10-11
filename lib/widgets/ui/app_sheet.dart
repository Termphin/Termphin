import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import 'sheet_handle.dart';

/// How the modal a widget sits in was presented. A sheet's content reads it
/// to drop what only a sheet has - the grab handle, the drag to resize - when
/// the same content opens as a dialog on a desktop.
enum ModalPresentation { sheet, dialog }

/// Carries [ModalPresentation] down to the content of [showAppSheet].
class AppModalScope extends InheritedWidget {
  const AppModalScope({
    super.key,
    required this.presentation,
    required super.child,
  });

  final ModalPresentation presentation;

  /// Outside any modal this reads as a sheet, which is what the content was
  /// written for.
  static ModalPresentation of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppModalScope>()
          ?.presentation ??
      ModalPresentation.sheet;

  static bool isDialog(BuildContext context) =>
      of(context) == ModalPresentation.dialog;

  @override
  bool updateShouldNotify(AppModalScope oldWidget) =>
      presentation != oldWidget.presentation;
}

/// Closes the modal it wraps on Esc - from wherever the focus is inside it.
///
/// Flutter ties Esc to the route only while nothing inside claims it first,
/// and a `Scaffold` does: it answers Esc for its drawer, open or not, so a
/// page in a dialog with a text field focused (a search box, a form) never
/// let Esc reach the route. Keys bubble up from the focused field, so this,
/// sitting above the page, hears Esc before anything the page holds. It
/// pops with `maybePop`, so a form with unsaved edits still gets to ask.
class EscapeToPop extends StatelessWidget {
  const EscapeToPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        unawaited(Navigator.of(context).maybePop());
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// Widest a modal grows on a desktop. Wider than that and a list of machines
/// reads as a table with nothing in its middle.
const double kAppDialogMaxWidth = 560;

/// Widest a form opened by [pushAppForm] grows.
const double kAppFormDialogMaxWidth = 680;

/// The tallest a modal is allowed to be in a window of [height].
double appDialogMaxHeight(double height) => math.min(760, height * 0.86);

/// The one way to open a bottom sheet - and, on a desktop, the dialog that
/// takes its place.
///
/// Every sheet used to pass its own `shape` - a rounded top identical to the
/// theme's - and then either drew a [SheetHandle], asked for Flutter's
/// `showDragHandle`, or had no grab bar at all, so the same gesture was
/// advertised three different ways and twice not at all. Shape and background
/// are left to `bottomSheetTheme`; the handle is drawn here.
///
/// A bottom sheet is a phone's answer to a modal: it comes up under the thumb
/// and is dragged away. A desktop has neither, so there the same content
/// opens as a dialog in the middle of the window, closed with Esc or a click
/// outside. The content does not need to know - [SheetHandle] hides itself
/// and [AppDraggableSheet] stops being draggable inside a dialog.
///
/// [handle] is for the one case that has to draw its own: a sheet whose
/// content is an [AppDraggableSheet] resizes below a bar placed here, so the
/// bar has to live inside that child to move with it.
///
/// [surface] is for a sheet whose colours must change while it is open. The
/// route keeps the theme it was pushed under, background included, so such a
/// sheet paints its own: the route's background goes invisible and the whole
/// sheet, handle and all, is handed to [surface] to wrap in a theme of its
/// choosing and draw the background in.
///
/// Only the handled sheet is inset for the navigation bar here: a sheet
/// that sizes itself with an [AppDraggableSheet] measures against the room
/// it is given, and would come up short by the navigation bar's height if
/// this inset it too, so that case is left for the caller to size itself.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool handle = true,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Widget Function(Widget sheet)? surface,
}) {
  if (isDesktopPlatform) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (ctx) => AppModalScope(
        presentation: ModalPresentation.dialog,
        child: isDismissible
            ? EscapeToPop(
                child: AppDialogFrame(child: Builder(builder: builder)),
              )
            : AppDialogFrame(child: Builder(builder: builder)),
      ),
    );
  }
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

/// The dialog a sheet's content is put in on a desktop: themed like every
/// other dialog, capped in width and height, and as tall as its content up
/// to that cap.
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    required this.child,
    this.maxWidth = kAppDialogMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: appDialogMaxHeight(height),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: child,
        ),
      ),
    );
  }
}

/// A sheet the user resizes by dragging its handle, or - in a dialog, where
/// nothing is dragged - a fixed share of the window.
///
/// The builder gets the scroll controller its list has to use: the sheet's own
/// while it is a sheet, so a drag on the list grows the sheet before it
/// scrolls; a plain one in a dialog.
class AppDraggableSheet extends StatefulWidget {
  const AppDraggableSheet({
    super.key,
    required this.builder,
    this.initialChildSize = 0.65,
    this.minChildSize = 0.4,
    this.maxChildSize = 0.9,
  });

  final Widget Function(BuildContext context, ScrollController controller)
  builder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  State<AppDraggableSheet> createState() => _AppDraggableSheetState();
}

class _AppDraggableSheetState extends State<AppDraggableSheet> {
  ScrollController? _dialogController;

  @override
  void dispose() {
    _dialogController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppModalScope.isDialog(context)) {
      final controller = _dialogController ??= ScrollController();
      final height = appDialogMaxHeight(MediaQuery.sizeOf(context).height);
      return SizedBox(
        height: height * widget.maxChildSize,
        child: widget.builder(context, controller),
      );
    }
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: widget.initialChildSize,
        minChildSize: widget.minChildSize,
        maxChildSize: widget.maxChildSize,
        expand: false,
        builder: widget.builder,
      ),
    );
  }
}

/// The route a desktop form or work window opens in: a dialog over the whole
/// window. A page in it that relies on its app bar's implied button gets an X
/// there rather than a back arrow - there is no page behind it to go back
/// to, only the window to close - and Esc does the same.
///
/// It is barrier-dismissible as far as the route is concerned, because that
/// is what Flutter ties Esc to - and Esc goes through `maybePop`, so a form
/// with unsaved edits still gets to ask. A click beside the dialog is caught
/// before it reaches the barrier instead (see [_pushDesktopDialog]): a
/// half-filled form is not something a stray click should throw away.
class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.settings,
  }) : super(barrierDismissible: true);
}

/// Pushes [builder] as a dialog over the whole window.
///
/// An opaque detector covers the window, so a click beside the dialog lands
/// on it and not on the barrier that would close it. A `Scaffold` sizes
/// itself to the room it is given, so the dialog is given a [height] to fill
/// rather than asked to shrink-wrap one.
Future<T?> _pushDesktopDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required double maxWidth,
  required double Function(Size window) height,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    AppDialogRoute<T>(
      context: context,
      builder: (ctx) {
        final window = MediaQuery.sizeOf(ctx);
        return AppModalScope(
          presentation: ModalPresentation.dialog,
          child: EscapeToPop(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Dialog(
                clipBehavior: Clip.antiAlias,
                insetPadding: const EdgeInsets.all(32),
                child: ActionIconTheme(
                  data: ActionIconThemeData(
                    backButtonIconBuilder: (_) =>
                        const Icon(PhosphorIconsRegular.x),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: SizedBox(
                      height: height(window),
                      child: Builder(builder: builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Opens a form: a full-screen page with a close button on a phone, a dialog
/// over the window on a desktop, where a form stretched edge to edge across a
/// 1600pt window reads as nothing but margins.
///
/// The page is the same widget either way. Its own app bar becomes the
/// dialog's header - its close button already says what Esc does.
/// [fullscreenDialogOnMobile] false keeps a phone's ordinary page, back arrow
/// and all, for a task that was never presented as a modal there.
Future<T?> pushAppForm<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool rootNavigator = false,
  double maxWidth = kAppFormDialogMaxWidth,
  bool fullscreenDialogOnMobile = true,
}) {
  if (isDesktopPlatform) {
    return _pushDesktopDialog<T>(
      context,
      builder: builder,
      maxWidth: maxWidth,
      height: (window) => appDialogMaxHeight(window.height),
    );
  }
  return Navigator.of(context, rootNavigator: rootNavigator).push<T>(
    MaterialPageRoute<T>(
      builder: builder,
      fullscreenDialog: fullscreenDialogOnMobile,
    ),
  );
}

/// Opens a page that is somewhere to work rather than a step in a list - the
/// file editor, an image viewer - from a place with no section of its own to
/// open it in, such as a session. A page over everything on a phone; on a
/// desktop a large window over the app, so the sidebar and the session it
/// came from are still there behind it.
Future<T?> pushAppWindow<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  AppWindowSize size = AppWindowSize.large,
}) {
  if (isDesktopPlatform) {
    return switch (size) {
      AppWindowSize.large => _pushDesktopDialog<T>(
        context,
        builder: builder,
        maxWidth: 1280,
        height: (window) => window.height * 0.9,
      ),
      AppWindowSize.medium => _pushDesktopDialog<T>(
        context,
        builder: builder,
        maxWidth: kAppSettingsWindowMaxWidth,
        height: (window) => appDialogMaxHeight(window.height),
      ),
    };
  }
  return Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: builder));
}

/// How much of the window a desktop window takes: [large] for somewhere to
/// work - an editor, an image - and [medium] for a page of settings, which
/// reads at a column's width and leaves the screen it came from in view.
enum AppWindowSize { large, medium }

/// Widest a [AppWindowSize.medium] window grows: the reading width a settings
/// page is laid out for, and its margins.
const double kAppSettingsWindowMaxWidth = 820;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

enum AppNotificationKind { error, success, info, warning }

/// Height of the app bar the toasts should slide out from under.
///
/// Screens whose app bar is not the default height write their own value here
/// (and restore it on the way out); everything else leaves it alone. The
/// overlay is not in any route's widget tree, so an InheritedWidget cannot
/// carry this down to it.
final ValueNotifier<double> appNotificationAnchor = ValueNotifier(
  kToolbarHeight,
);

/// Toasts that slide out from beneath the app bar and stack below it.
///
/// Replaces `ScaffoldMessenger` snackbars: those dock to the bottom, where the
/// nav bar, the session dock and the terminal key toolbar already live, and
/// they queue one at a time so a burst of results is shown over ten seconds
/// instead of at once.
///
/// The stack lives and dies as one. A tap or a swipe clears all of it, and it
/// times out on the newest card's deadline rather than each card's own - a
/// toast raised a moment ago should not vanish because an older one beside it
/// ran out.
class AppNotifications {
  const AppNotifications._();

  static const _defaultDuration = Duration(seconds: 4);
  static const _actionDuration = Duration(seconds: 8);
  static const maxVisible = 3;

  static _NotificationHostState? _host;
  static OverlayEntry? _entry;

  /// Shown before the host has built. Inserting an [OverlayEntry] only marks
  /// the overlay dirty, so the very first notification is raised a frame
  /// before there is anything to hand it to.
  static final _pending = <_NotificationData>[];

  static void error(BuildContext context, String message) =>
      show(context, message, kind: AppNotificationKind.error);

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    kind: AppNotificationKind.success,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void info(BuildContext context, String message) =>
      show(context, message, kind: AppNotificationKind.info);

  static void warning(BuildContext context, String message) =>
      show(context, message, kind: AppNotificationKind.warning);

  /// [context] may also be the root overlay's own, from [anchorOf] - for a
  /// result that arrives after the widget that asked for it is gone.
  static void show(
    BuildContext context,
    String message, {
    required AppNotificationKind kind,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ??
        switch (context) {
          StatefulElement(:final OverlayState state) => state,
          _ => null,
        };
    if (overlay == null) return;
    _mount(overlay);
    final data = _NotificationData(
      message: message,
      kind: kind,
      actionLabel: onAction == null ? null : actionLabel,
      onAction: actionLabel == null ? null : onAction,
      duration:
          duration ?? (onAction == null ? _defaultDuration : _actionDuration),
    );
    final host = _host;
    if (host == null || !host.mounted) {
      _pending.add(data);
      return;
    }
    host.push(data);
  }

  /// A context that outlives [context]'s widget, for a notification raised
  /// once that widget may have closed. Check `mounted` on it before use.
  static BuildContext anchorOf(BuildContext context) =>
      Overlay.of(context, rootOverlay: true).context;

  /// Clears the stack - for a screen that is about to show its own result and
  /// does not want the previous one lingering over it.
  static void dismissAll() {
    _pending.clear();
    _host?.closeAll();
  }

  /// The overlay [_entry] was inserted into.
  static OverlayState? _overlay;

  /// An existing entry already inserted but not built yet - a second toast
  /// in the frame that raised the first - is left alone rather than
  /// disposed: its host takes [_pending] when it builds, and disposing an
  /// entry still in the overlay is what used to blank the whole screen.
  static void _mount(OverlayState overlay) {
    if (_host != null && _host!.mounted) return;
    if (_entry != null && identical(_overlay, overlay) && overlay.mounted) {
      return;
    }
    _overlay = overlay;
    _entry = OverlayEntry(
      builder: (_) =>
          _NotificationHost(onStateCreated: (state) => _host = state),
    );
    overlay.insert(_entry!);
  }
}

class _NotificationData {
  _NotificationData({
    required this.message,
    required this.kind,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppNotificationKind kind;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  final key = UniqueKey();
}

class _NotificationHost extends StatefulWidget {
  const _NotificationHost({required this.onStateCreated});

  final void Function(_NotificationHostState) onStateCreated;

  @override
  State<_NotificationHost> createState() => _NotificationHostState();
}

/// The stack is clipped to the strip below the app bar, so a card animating
/// in from above is hidden until it clears the bar - it reads as sliding out
/// from under it.
class _NotificationHostState extends State<_NotificationHost> {
  final _items = <_NotificationData>[];

  /// Bumped to tell every card on screen to play its exit. Each one removes
  /// itself through [_dismiss] when the animation lands.
  final _closeSignal = ValueNotifier(0);

  Timer? _timer;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
    for (final data in AppNotifications._pending) {
      _items.insert(0, data);
      _extendDeadline(data.duration);
    }
    _trim();
    AppNotifications._pending.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _closeSignal.dispose();
    if (identical(AppNotifications._host, this)) {
      AppNotifications._host = null;
      AppNotifications._entry = null;
    }
    super.dispose();
  }

  void push(_NotificationData data) {
    HapticFeedback.selectionClick();
    setState(() {
      _items.insert(0, data);
      _trim();
    });
    _extendDeadline(data.duration);
  }

  /// Pushes the shared expiry out to cover [duration], never pulling it in -
  /// a plain toast landing on top of one with an action must not cut the
  /// action's longer window short.
  void _extendDeadline(Duration duration) {
    final next = DateTime.now().add(duration);
    if (_deadline != null && !next.isAfter(_deadline!)) return;
    _deadline = next;
    _timer?.cancel();
    _timer = Timer(duration, closeAll);
  }

  /// Trims from the bottom: the oldest toast is the one the user has had the
  /// longest to read.
  void _trim() {
    while (_items.length > AppNotifications.maxVisible) {
      _items.removeLast();
    }
  }

  void closeAll() {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
    if (_items.isEmpty) return;
    _closeSignal.value++;
  }

  void _dismiss(_NotificationData data) {
    if (!_items.contains(data)) return;
    setState(() => _items.remove(data));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appNotificationAnchor,
      builder: (context, anchor, _) {
        final top = MediaQuery.paddingOf(context).top + anchor;
        return Positioned(
          top: top,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRect(
                clipper: const _TopOverflowClipper(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in _items)
                      _NotificationCard(
                        key: item.key,
                        data: item,
                        closeSignal: _closeSignal,
                        onCloseAll: closeAll,
                        onDismissed: () => _dismiss(item),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Clips the top edge only, leaving room below and to the sides for shadows.
class _TopOverflowClipper extends CustomClipper<Rect> {
  const _TopOverflowClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-40, 0, size.width + 40, size.height + 80);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    super.key,
    required this.data,
    required this.closeSignal,
    required this.onCloseAll,
    required this.onDismissed,
  });

  final _NotificationData data;

  /// Fires when the whole stack is going away.
  final Listenable closeSignal;

  final VoidCallback onCloseAll;

  /// Called once this card's exit animation has finished.
  final VoidCallback onDismissed;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTheme.motionSlow,
    reverseDuration: AppTheme.interactiveDuration,
  );
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    widget.closeSignal.addListener(_close);
  }

  @override
  void dispose() {
    widget.closeSignal.removeListener(_close);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _controller.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  /// Upwards only - the toast retreats the way it came in.
  void _onDragUpdate(DragUpdateDetails details) {
    final limit = -(context.size?.height ?? 200);
    setState(
      () => _dragOffset = (_dragOffset + details.delta.dy).clamp(limit, 0.0),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final flungUp = details.velocity.pixelsPerSecond.dy < -300;
    if (flungUp || _dragOffset < -28) {
      widget.onCloseAll();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  (Color, IconData) get _style => switch (widget.data.kind) {
    AppNotificationKind.error => (
      context.colors.error,
      PhosphorIconsFill.xCircle,
    ),
    AppNotificationKind.success => (
      context.colors.success,
      PhosphorIconsRegular.checkCircle,
    ),
    AppNotificationKind.warning => (
      context.colors.warning,
      PhosphorIconsFill.warning,
    ),
    AppNotificationKind.info => (
      context.colors.textSecondary,
      PhosphorIconsFill.info,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _style;
    final data = widget.data;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.35),
            end: Offset.zero,
          ).animate(curve),
          child: FadeTransition(
            opacity: curve,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: GestureDetector(
                onTap: data.onAction == null ? widget.onCloseAll : null,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                child: Material(
                  color: context.colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  elevation: 6,
                  shadowColor: Colors.black54,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 21, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              data.message,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: context.colors.textPrimary,
                                    fontSize: 14.5,
                                    height: 1.35,
                                  ),
                            ),
                          ),
                        ),
                        if (data.actionLabel != null) ...[
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () {
                              data.onAction?.call();
                              widget.onCloseAll();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(data.actionLabel!),
                          ),
                        ] else
                          const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

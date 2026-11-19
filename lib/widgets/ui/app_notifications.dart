import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';

/// What a toast is about. [alert] is a program in another session asking
/// for attention while Termphin is in front, the in-app stand-in for the
/// system notification it would otherwise post.
enum AppNotificationKind { error, success, info, warning, alert }

/// Toasts that drop in at the top of the screen, just under the status bar.
///
/// Replaces `ScaffoldMessenger` snackbars: those dock to the bottom, where the
/// nav bar, the session dock and the terminal key toolbar already live, and
/// they queue one at a time so a burst of results is shown over ten seconds
/// instead of at once.
///
/// A short message with nothing to tap is a pill centred at the top, small
/// enough to leave the app bar and the terminal's tabs readable. Anything
/// longer, with a title or with an action, opens up into a card tinted with
/// its kind. The same message raised again while it is still up is counted
/// on the one already there rather than stacked under it.
///
/// The stack lives and dies as one. A tap or a swipe clears all of it, and it
/// times out on the newest card's deadline rather than each card's own - a
/// toast raised a moment ago should not vanish because an older one beside it
/// ran out. How long one stays follows how long it takes to read.
///
/// Only what needs attention is felt: an error gives one buzz, an alert two,
/// a confirmation none. Screen readers hear every toast as it arrives.
class AppNotifications {
  const AppNotifications._();

  static const _shortest = Duration(seconds: 4);
  static const _shortestError = Duration(seconds: 6);
  static const _actionDuration = Duration(seconds: 8);

  /// An alert is news the user may be waiting on and may only catch from
  /// the corner of an eye, so it outlasts everything else.
  static const _alertDuration = Duration(seconds: 12);
  static const maxVisible = 3;

  /// Characters read in the shortest time; every one past them adds
  /// [_perCharacter].
  static const _glanceLength = 40;
  static const _perCharacter = Duration(milliseconds: 50);

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

  /// A program in another session asking for attention: [title] says what
  /// happened, [body] the line it ended on. A tap anywhere on the card does
  /// the same as [actionLabel]: [onOpen]. It stays longer than any other
  /// toast.
  static void alert(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onOpen,
  }) => show(
    context,
    body,
    title: title,
    kind: AppNotificationKind.alert,
    actionLabel: actionLabel,
    onAction: onOpen,
  );

  /// [context] may also be the root overlay's own, from [anchorOf] - for a
  /// result that arrives after the widget that asked for it is gone - or a
  /// navigator's own, from a navigator key: what sits above the app's routes
  /// has no overlay above it, only the navigator's beneath.
  static void show(
    BuildContext context,
    String message, {
    required AppNotificationKind kind,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ??
        switch (context) {
          StatefulElement(:final OverlayState state) => state,
          StatefulElement(:final NavigatorState state) => state.overlay,
          _ => null,
        };
    if (overlay == null) return;
    _mount(overlay);
    final hasAction = onAction != null && actionLabel != null;
    final data = _NotificationData(
      message: message,
      title: title,
      kind: kind,
      actionLabel: hasAction ? actionLabel : null,
      onAction: hasAction ? onAction : null,
      duration: duration ?? durationFor(kind, message, hasAction: hasAction),
    );
    final host = _host;
    if (host == null || !host.mounted) {
      _pending.add(data);
      return;
    }
    host.push(data);
  }

  /// How long a toast of [kind] saying [message] stays: long enough to read,
  /// longer for an error, whose words matter more than a confirmation's,
  /// longer with an action, which needs time to reach for, and the longest
  /// for an alert.
  @visibleForTesting
  static Duration durationFor(
    AppNotificationKind kind,
    String message, {
    required bool hasAction,
  }) {
    if (kind == AppNotificationKind.alert) return _alertDuration;
    if (hasAction) return _actionDuration;
    final extra = math.max(0, message.length - _glanceLength);
    final reading = _shortest + _perCharacter * extra;
    final floor = kind == AppNotificationKind.error
        ? _shortestError
        : _shortest;
    if (reading < floor) return floor;
    return reading > _actionDuration ? _actionDuration : reading;
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
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final AppNotificationKind kind;
  final Duration duration;
  final String? actionLabel;
  VoidCallback? onAction;

  /// How many times the same toast was raised while this one was up.
  int count = 1;

  final key = UniqueKey();

  bool repeats(_NotificationData other) =>
      other.kind == kind &&
      other.title == title &&
      other.message == message &&
      other.actionLabel == actionLabel;
}

class _NotificationHost extends StatefulWidget {
  const _NotificationHost({required this.onStateCreated});

  final void Function(_NotificationHostState) onStateCreated;

  @override
  State<_NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<_NotificationHost> {
  final _items = <_NotificationData>[];

  /// Bumped to tell every card on screen to play its exit. Each one removes
  /// itself through [_dismiss] when the animation lands.
  final _closeSignal = ValueNotifier(0);

  Timer? _timer;
  Timer? _secondBuzz;
  DateTime? _deadline;

  /// The gap between an alert's two buzzes, short enough to read as one
  /// signal and long enough to be told apart from an error's single one.
  static const _buzzGap = Duration(milliseconds: 140);

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
    for (final data in AppNotifications._pending) {
      _add(data);
    }
    AppNotifications._pending.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondBuzz?.cancel();
    _closeSignal.dispose();
    if (identical(AppNotifications._host, this)) {
      AppNotifications._host = null;
      AppNotifications._entry = null;
    }
    super.dispose();
  }

  void push(_NotificationData data) => setState(() => _add(data));

  void _add(_NotificationData data) {
    _buzz(data.kind);
    final shown = _items.where(data.repeats).firstOrNull;
    if (shown != null) {
      shown
        ..count += 1
        ..onAction = data.onAction;
    } else {
      _items.insert(0, data);
      _trim();
    }
    _extendDeadline(data.duration);
  }

  void _buzz(AppNotificationKind kind) {
    switch (kind) {
      case AppNotificationKind.alert:
        unawaited(HapticFeedback.mediumImpact());
        _secondBuzz?.cancel();
        _secondBuzz = Timer(
          _buzzGap,
          () => unawaited(HapticFeedback.mediumImpact()),
        );
      case AppNotificationKind.error:
        unawaited(HapticFeedback.mediumImpact());
      case AppNotificationKind.warning:
        unawaited(HapticFeedback.lightImpact());
      case AppNotificationKind.success || AppNotificationKind.info:
        break;
    }
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

  /// A strip across a 1600pt window is a banner nobody reads; a desktop
  /// stacks the notifications in the corner instead, at a card's width.
  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + AppTheme.space6,
      left: desktop ? null : 0,
      right: desktop ? AppTheme.space8 : 0,
      width: desktop ? 420 : null,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12),
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
    );
  }
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

  void _runAction() {
    widget.data.onAction?.call();
    widget.onCloseAll();
  }

  /// An alert's whole card is the way to its session; a toast with an action
  /// leaves the tap to its button, so a stray touch does not run it.
  VoidCallback? get _onTap => switch (widget.data) {
    _NotificationData(kind: AppNotificationKind.alert) => _runAction,
    _NotificationData(onAction: null) => widget.onCloseAll,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.space8),
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
                onTap: _onTap,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _fitsPill(context, constraints.maxWidth)
                        ? Center(child: _Pill(data: widget.data))
                        : _Card(data: widget.data, onAction: _runAction),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A pill holds one line and nothing to tap. Measured rather than counted,
  /// since the width of a character depends on the font and the text scale.
  bool _fitsPill(BuildContext context, double maxWidth) {
    final data = widget.data;
    if (data.title != null || data.actionLabel != null) return false;
    final reserved =
        _Pill.padding.horizontal +
        AppTheme.icon18 +
        AppTheme.space8 +
        (data.count > 1 ? AppTheme.space40 : 0);
    final painter = TextPainter(
      text: TextSpan(text: data.message, style: _Pill.textStyle(context)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(0, maxWidth - reserved));
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }
}

/// The colour that marks a toast's kind and the icon that names it.
(Color, IconData) _accent(BuildContext context, AppNotificationKind kind) {
  final colors = context.colors;
  return switch (kind) {
    AppNotificationKind.error => (colors.error, PhosphorIconsRegular.xCircle),
    AppNotificationKind.success => (
      colors.success,
      PhosphorIconsRegular.checkCircle,
    ),
    AppNotificationKind.warning => (
      colors.warning,
      PhosphorIconsRegular.warning,
    ),
    AppNotificationKind.info => (colors.primary, PhosphorIconsRegular.info),
    AppNotificationKind.alert => (
      colors.primary,
      PhosphorIconsRegular.terminal,
    ),
  };
}

/// One line and an icon in a capsule, for a confirmation read at a glance.
class _Pill extends StatelessWidget {
  const _Pill({required this.data});

  final _NotificationData data;

  static const padding = EdgeInsets.fromLTRB(
    AppTheme.space12,
    AppTheme.space10,
    AppTheme.space16,
    AppTheme.space10,
  );

  static TextStyle? textStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: context.colors.textPrimary,
        fontSize: AppTheme.font14,
        fontWeight: FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (accent, icon) = _accent(context, data.kind);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: colors.surfaceBorderStrong,
          width: AppTheme.hairline,
        ),
        boxShadow: colors.isDark ? AppTheme.popupShadow : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.icon18, color: accent),
          const SizedBox(width: AppTheme.space8),
          Flexible(
            child: Text(
              data.message,
              style: textStyle(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (data.count > 1) ...[
            const SizedBox(width: AppTheme.space6),
            _RepeatBadge(count: data.count, color: accent),
          ],
        ],
      ),
    );
  }
}

/// The full card: the kind's tint, an optional title, the message on as many
/// lines as it needs and an optional action. An alert keeps the neutral
/// surface and wears the app's mark, the way the system shows Termphin's
/// own notifications.
class _Card extends StatelessWidget {
  const _Card({required this.data, required this.onAction});

  final _NotificationData data;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final (accent, icon) = _accent(context, data.kind);
    final alert = data.kind == AppNotificationKind.alert;
    final (background, border) = switch (data.kind) {
      AppNotificationKind.error => (colors.errorHighlight, colors.error),
      AppNotificationKind.success => (colors.successHighlight, colors.success),
      AppNotificationKind.warning => (colors.warningHighlight, colors.warning),
      AppNotificationKind.info => (colors.primaryHighlight, colors.primary),
      AppNotificationKind.alert => (
        colors.surfaceElevated,
        colors.surfaceBorderStrong,
      ),
    };
    final title = data.title;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(
          color: alert ? border : border.withValues(alpha: 0.45),
          width: AppTheme.hairline,
        ),
      ),
      shadowColor: colors.isDark ? AppTheme.shadowColor : null,
      elevation: colors.isDark ? AppTheme.space6 : 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space14,
          AppTheme.space12,
          AppTheme.space8,
          AppTheme.space12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert)
              Container(
                width: AppTheme.icon28,
                height: AppTheme.icon28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: AppTheme.icon16,
                  color: colors.onPrimary,
                ),
              )
            else
              Icon(icon, size: AppTheme.icon20, color: accent),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontSize: AppTheme.font14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (data.count > 1) ...[
                          const SizedBox(width: AppTheme.space6),
                          _RepeatBadge(count: data.count, color: accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppTheme.space2),
                  ],
                  Text(
                    data.message,
                    style: text.bodyMedium?.copyWith(
                      color: title == null
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontSize: title == null
                          ? AppTheme.font14
                          : AppTheme.font13,
                      height: 1.35,
                    ),
                    maxLines: alert ? 2 : null,
                    overflow: alert ? TextOverflow.ellipsis : null,
                  ),
                  if (title == null && data.count > 1) ...[
                    const SizedBox(height: AppTheme.space4),
                    _RepeatBadge(count: data.count, color: accent),
                  ],
                ],
              ),
            ),
            if (data.actionLabel case final label?) ...[
              const SizedBox(width: AppTheme.space4),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space10,
                  ),
                  minimumSize: const Size(0, AppTheme.space32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(label),
              ),
            ] else
              const SizedBox(width: AppTheme.space6),
          ],
        ),
      ),
    );
  }
}

/// "×2": the same toast raised again while it was still up.
class _RepeatBadge extends StatelessWidget {
  const _RepeatBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space6,
        vertical: AppTheme.hairline,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        t.common.repeatCount(count: count),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: AppTheme.font11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

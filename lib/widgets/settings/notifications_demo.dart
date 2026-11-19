import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';

/// What the notifications look like, above their settings: example
/// notifications arrive the way the system shows them, the newest sliding
/// in on top and the oldest leaving at the bottom.
///
/// The frame holds two notifications and never changes size, so the
/// settings under it stay where they are. It goes through every example
/// once, starting as the screen has finished sliding in, and stops on the
/// last two; with animations turned off in the system it shows those
/// straight away. Each card is drawn once and then only moved and faded,
/// so a frame of the animation costs no layout and no repaint of the text.
///
/// Decoration only, hidden from screen readers: the screen's subtitle says
/// the same in words.
class NotificationsDemo extends StatefulWidget {
  const NotificationsDemo({super.key});

  /// How long each arrival takes, with the pause after it.
  static const step = Duration(milliseconds: 1600);

  /// How many arrivals it plays before it stops.
  static const steps = 5;

  @override
  State<NotificationsDemo> createState() => _NotificationsDemoState();
}

class _NotificationsDemoState extends State<NotificationsDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: NotificationsDemo.step * NotificationsDemo.steps,
  )..addListener(_onTick);

  /// The arrival playing now. Only a new arrival changes which cards are on
  /// screen; in between, the cards already there are only moved and faded.
  int _step = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
    } else if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterEntrance());
    }
  }

  /// Played while the screen is still sliding in, the first arrival shares
  /// its frames with the slide and with the sections below loading in, and
  /// stutters; it waits for the screen to land.
  ///
  /// Asked a frame in: on the first build the route's animation is not
  /// hooked up yet and reads as already finished.
  void _afterEntrance() {
    if (!mounted) return;
    final entrance = ModalRoute.of(context)?.animation;
    if (entrance == null || entrance.isCompleted) {
      _clock.forward();
      return;
    }
    void landed(AnimationStatus status) {
      if (!status.isCompleted) return;
      entrance.removeStatusListener(landed);
      if (mounted) _clock.forward();
    }

    entrance.addStatusListener(landed);
  }

  void _onTick() {
    final step = _stepAt(_clock.value);
    if (step != _step) setState(() => _step = step);
  }

  static int _stepAt(double value) => math.min(
    (value * NotificationsDemo.steps).floor(),
    NotificationsDemo.steps - 1,
  );

  /// How far the arrival of [_step] has got, eased: it moves in the first
  /// part of its step and holds for the rest.
  double get _eased {
    final position = _clock.value * NotificationsDemo.steps;
    final moving = ((position - _step) / 0.4).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(moving);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = Translations.of(context).settings.notificationsDemo;
    final notices = [
      _Notice(title: demo.finishedTitle, body: demo.finishedBody),
      _Notice(title: demo.waitingTitle, body: demo.waitingBody),
      _Notice(title: demo.testsTitle, body: demo.testsBody),
    ];
    _step = _stepAt(_clock.value);
    final newest = _step + 1;
    return ExcludeSemantics(
      child: ClipRect(
        child: Stack(
          children: [
            Opacity(
              opacity: 0,
              child: Column(children: [_slot(notices[0]), _slot(notices[1])]),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxHeight / 2;
                  return Stack(
                    children: [
                      for (final age in const [2, 1, 0])
                        if (newest - age >= 0)
                          Positioned(
                            key: ValueKey(newest - age),
                            left: 0,
                            right: 0,
                            top: 0,
                            child: AnimatedBuilder(
                              animation: _clock,
                              builder: (context, child) {
                                final eased = _eased;
                                final (offset, opacity) = switch (age) {
                                  2 => (slot + eased * slot, 1 - eased),
                                  1 => (eased * slot, 1.0),
                                  _ => ((eased - 1) * slot, eased),
                                };
                                return Transform.translate(
                                  offset: Offset(0, offset),
                                  child: Opacity(
                                    opacity: opacity,
                                    child: child,
                                  ),
                                );
                              },
                              child: RepaintBoundary(
                                child: _slot(
                                  notices[(newest - age) % notices.length],
                                ),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(Widget notice) => Padding(
    padding: const EdgeInsets.only(bottom: AppTheme.space8),
    child: notice,
  );
}

/// One notification as the system draws it: the app's mark and name, then
/// the title naming the command and the line it ended on.
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final t = Translations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppTheme.icon28,
            height: AppTheme.icon28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIconsRegular.terminal,
              size: AppTheme.icon16,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(width: AppTheme.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.settings.notificationsDemo.appLine,
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
                Text(
                  title,
                  style: text.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  body,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
/// once as the screen opens and stops on the last two; with animations
/// turned off in the system it shows those straight away.
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
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
    } else if (!_clock.isAnimating && _clock.value == 0) {
      _clock.forward();
    }
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
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _clock,
                  builder: (context, _) =>
                      _frame(notices, constraints.maxHeight / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The notifications on screen at this moment: the one arriving, the one
  /// it pushes into the second row, and the one it pushes out.
  Widget _frame(List<_Notice> notices, double slot) {
    final position = _clock.value * NotificationsDemo.steps;
    final step = math.min(position.floor(), NotificationsDemo.steps - 1);
    final moving = ((position - step) / 0.4).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(moving);
    final newest = step + 1;
    return Stack(
      children: [
        for (final (age, offset, opacity) in [
          (2, slot + eased * slot, 1 - eased),
          (1, eased * slot, 1.0),
          (0, (eased - 1) * slot, eased),
        ])
          if (newest - age >= 0)
            Positioned(
              left: 0,
              right: 0,
              top: offset,
              child: Opacity(
                opacity: opacity,
                child: _slot(notices[(newest - age) % notices.length]),
              ),
            ),
      ],
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

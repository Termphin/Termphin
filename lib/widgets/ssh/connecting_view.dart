import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../theme/theme.dart';

class ConnectingView extends ConsumerStatefulWidget {
  const ConnectingView({
    super.key,
    required this.profile,
    required this.onCancel,
    this.connectionLog = const [],
    this.reconnectAttempt = 0,
    this.reconnectSecondsRemaining = 0,
    this.waitingForNetwork = false,
    this.restoringHistory = false,
  });
  final SshProfile profile;
  final VoidCallback onCancel;
  final List<String> connectionLog;
  final int reconnectAttempt;
  final int reconnectSecondsRemaining;

  /// Parked with no countdown until the device has a network again.
  final bool waitingForNetwork;

  /// The transport is up and the scrollback is being painted into a terminal
  /// that is not on screen yet.
  final bool restoringHistory;

  @override
  ConsumerState<ConnectingView> createState() => _ConnectingViewState();
}

/// Waiting on the radio counts as reconnecting even before an attempt has
/// been spent - the ring and the warning colour are what say the session is
/// not simply opening for the first time.
class _ConnectingViewState extends ConsumerState<ConnectingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    if (widget.connectionLog.isNotEmpty) _scrollLogToBottom();
  }

  @override
  void didUpdateWidget(ConnectingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connectionLog.length > oldWidget.connectionLog.length) {
      _scrollLogToBottom();
    }
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logScrollController.hasClients) return;
      _logScrollController.jumpTo(
        _logScrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final profile = widget.profile;
    final reconnecting =
        widget.reconnectAttempt > 0 || widget.waitingForNetwork;
    final anonymize = ref.watch(anonymizeProvider);
    final displayName = anonymize
        ? IdentityAnonymizer.name(profile.id)
        : profile.name;
    final displayLog = anonymize
        ? anonymizeConnectionLog(widget.connectionLog, profile)
        : widget.connectionLog;

    return SizedBox.expand(
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              bottom: 72,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RotationTransition(
                          turns: _ctrl,
                          child: CustomPaint(
                            size: const Size(40, 40),
                            painter: _RingPainter(
                              color: reconnecting
                                  ? context.colors.warning
                                  : context.colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.restoringHistory
                              ? t.connection.restoringHistory
                              : widget.waitingForNetwork
                              ? t.connection.waitingForNetwork
                              : reconnecting
                              ? t.connection.reconnecting(
                                  attempt: widget.reconnectAttempt,
                                )
                              : t.connection.connecting,
                          style: TextStyle(
                            fontSize: 13,
                            color: reconnecting
                                ? context.colors.warning
                                : context.colors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (reconnecting &&
                            widget.reconnectSecondsRemaining > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            t.connection.reconnectingIn(
                              seconds: widget.reconnectSecondsRemaining,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 154,
                          child: AnimatedSwitcher(
                            duration: AppTheme.motionSlow,
                            switchInCurve: AppTheme.interactiveCurve,
                            child: displayLog.isEmpty
                                ? const SizedBox.expand(
                                    key: ValueKey('empty-connection-log'),
                                  )
                                : _ConnectionLogPanel(
                                    key: const ValueKey(
                                      'visible-connection-log',
                                    ),
                                    lines: displayLog,
                                    controller: _logScrollController,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: TextButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(PhosphorIconsRegular.x, size: 16),
                  label: Text(t.common.cancel),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fills the fixed-height box the switcher sits in; the switcher hands out
/// loose constraints, so without an explicit height the card would grow
/// line by line instead of staying put while the log scrolls inside it.
class _ConnectionLogPanel extends StatelessWidget {
  const _ConnectionLogPanel({
    super.key,
    required this.lines,
    required this.controller,
  });

  final List<String> lines;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SelectionArea(
        child: Scrollbar(
          controller: controller,
          thumbVisibility: false,
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < lines.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == lines.length - 1 ? 0 : 7,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 6, right: 9),
                          decoration: BoxDecoration(
                            color: index == lines.length - 1
                                ? context.colors.primary
                                : context.colors.textTertiary.withValues(
                                    alpha: 0.35,
                                  ),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXs,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            lines[index],
                            style: context.colors.monoSmall.copyWith(
                              height: 1.4,
                              color: index == lines.length - 1
                                  ? context.colors.textSecondary
                                  : context.colors.textTertiary.withValues(
                                      alpha: 0.72,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    paint.color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, paint);

    paint.shader = SweepGradient(
      startAngle: 0,
      endAngle: 3.14159 * 2,
      colors: [color.withValues(alpha: 0), color],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      3.14159 * 1.4,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldPainter) =>
      oldPainter.color != color;
}

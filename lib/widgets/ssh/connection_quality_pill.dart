import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/ssh/connection_quality.dart';
import '../../theme/theme.dart';

/// Says the connection is in trouble, in the corner of the terminal - and
/// says nothing at all while it is fine.
///
/// Drawn over the terminal rather than beside it: taking room from the pane
/// would resize the remote pty, the last thing to do to a struggling link.
class ConnectionQualityPill extends StatefulWidget {
  const ConnectionQualityPill({
    super.key,
    required this.quality,
    required this.onTap,
  });

  final ConnectionQuality quality;

  final VoidCallback onTap;

  @override
  State<ConnectionQualityPill> createState() => _ConnectionQualityPillState();
}

class _ConnectionQualityPillState extends State<ConnectionQualityPill> {
  Timer? _clock;

  /// Silence only shows up by time passing; this clock is also what moves
  /// the counter once the pill is on screen.
  @override
  void initState() {
    super.initState();
    widget.quality.addListener(_onChanged);
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => widget.quality.evaluate(),
    );
  }

  @override
  void didUpdateWidget(covariant ConnectionQualityPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quality != widget.quality) {
      oldWidget.quality.removeListener(_onChanged);
      widget.quality.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.quality.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final quality = widget.quality;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (quality.health) {
        ConnectionHealth.good => const SizedBox.shrink(),
        ConnectionHealth.slow => _Pill(
          key: const ValueKey(ConnectionHealth.slow),
          icon: PhosphorIconsFill.cellSignalLow,
          color: context.colors.warning,
          label: Translations.of(
            context,
          ).connection.quality.slow(ms: quality.recentLatency ?? 0),
          onTap: widget.onTap,
        ),
        ConnectionHealth.unresponsive => _Pill(
          key: const ValueKey(ConnectionHealth.unresponsive),
          icon: PhosphorIconsFill.warning,
          color: context.colors.error,
          label: Translations.of(
            context,
          ).connection.quality.unresponsive(seconds: quality.silence.inSeconds),
          onTap: widget.onTap,
        ),
      },
    );
  }
}

/// Stands in for [ConnectionQualityPill] while the session is reconnecting
/// under a terminal kept on screen: an icon in a ring that spins while a
/// retry is under way, except while waiting for the network, when there is
/// nothing to spin for. No words over the terminal - they are in the
/// tooltip and the semantics label, and the connection log a tap opens.
class ReconnectingIndicator extends StatelessWidget {
  const ReconnectingIndicator({
    super.key,
    required this.attempt,
    required this.secondsRemaining,
    required this.waitingForNetwork,
    required this.queuedInput,
    required this.onTap,
  });

  static const _size = 32.0;

  final int attempt;
  final int secondsRemaining;
  final bool waitingForNetwork;
  final int queuedInput;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final status = waitingForNetwork
        ? t.connection.waitingForNetwork
        : secondsRemaining > 0
        ? t.connection.reconnectingIn(seconds: secondsRemaining)
        : t.connection.reconnecting(attempt: attempt);
    final label = queuedInput > 0
        ? '$status\n${t.connection.quality.queued(n: queuedInput)}'
        : status;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: colors.surfaceElevated.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: _size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!waitingForNetwork)
                    SizedBox.square(
                      dimension: _size - 4,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.warning,
                      ),
                    ),
                  Icon(
                    waitingForNetwork
                        ? PhosphorIconsFill.wifiSlash
                        : PhosphorIconsFill.plugs,
                    size: 14,
                    color: colors.warning,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: Translations.of(context).connection.quality.openDetails,
      child: Material(
        color: colors.surfaceElevated.withValues(alpha: 0.92),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

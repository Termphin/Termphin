import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/port_forwarding_rule.dart';
import '../../theme/theme.dart';

/// One forwarding rule, as drawn everywhere a rule is listed - the tunnels
/// panel over a session and the port forwarding section of the profile form.
///
/// Both used to draw their own near-identical card out of hardcoded 9, 10 and
/// 12 point text, so the same rule read at two different scales depending on
/// which screen you reached it from. This is a row, not a card: callers stack
/// several into one [AppCard.fields] separated by [AppDivider]s, rather than
/// giving every rule a frame of its own.
///
/// [status] is null where there is no live tunnel to report on - the profile
/// form edits rules for a connection that does not exist yet.
///
/// The listening end is on the device for a local forward and on the server
/// for a remote one, so the arrow is drawn to read left to right in both.
class PortForwardingRuleTile extends StatelessWidget {
  const PortForwardingRuleTile({
    super.key,
    required this.rule,
    this.status,
    this.errorMessage,
    this.onTap,
    this.onToggle,
    this.onDelete,
  });

  final PortForwardingRule rule;
  final TunnelStatus? status;

  /// Why the server refused, when it did. Worth the room: "Error" on its own
  /// leaves no way to tell a port already in use from a server that has
  /// `AllowTcpForwarding` off, and both land here.
  final String? errorMessage;

  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final isLocal = rule.type == ForwardType.local;
    final accent = isLocal ? colors.primary : colors.warning;

    final sourceLabel = isLocal
        ? t.portForwarding.arrowDevice
        : t.portForwarding.arrowServer;
    final destLabel = isLocal
        ? t.portForwarding.arrowServer
        : t.portForwarding.arrowDevice;
    final sourcePort = isLocal ? rule.localPort : rule.remotePort;
    final destPort = isLocal ? rule.remotePort : rule.localPort;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Icon(
          isLocal
              ? PhosphorIconsFill.arrowLineDown
              : PhosphorIconsFill.arrowLineUp,
          size: 18,
          color: accent,
        ),
      ),
      title: Text(
        rule.displayName,
        style: colors.uiStyle.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EndpointLine(
              sourceLabel: sourceLabel,
              sourcePort: sourcePort,
              destLabel: destLabel,
              destPort: destPort,
              accent: accent,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  isLocal
                      ? t.portForwarding.localForward
                      : t.portForwarding.remoteForward,
                  style: colors.uiSmall.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                if (_statusText(t) case final text?) ...[
                  Text(' · ', style: colors.uiSmall.copyWith(fontSize: 11)),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: colors.uiSmall.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: status == TunnelStatus.error
                            ? colors.error
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (status == TunnelStatus.error && errorMessage != null) ...[
              const SizedBox(height: 3),
              Text(
                errorMessage!,
                style: colors.uiSmall.copyWith(
                  fontSize: 11,
                  color: colors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggle != null)
            Switch(
              value: status == TunnelStatus.active,
              onChanged: (_) => onToggle!(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          if (onDelete != null)
            IconButton(
              tooltip: t.common.delete,
              onPressed: onDelete,
              icon: Icon(
                PhosphorIconsFill.trash,
                size: 16,
                color: colors.textTertiary,
              ),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  /// Only the two states the switch cannot show on its own. Active is what a
  /// switch that is on already says, and idle is what one that is off says.
  String? _statusText(Translations t) => switch (status) {
    TunnelStatus.starting => t.portForwarding.statusStarting,
    TunnelStatus.error => t.portForwarding.statusError,
    _ => null,
  };
}

class _EndpointLine extends StatelessWidget {
  const _EndpointLine({
    required this.sourceLabel,
    required this.sourcePort,
    required this.destLabel,
    required this.destPort,
    required this.accent,
  });

  final String sourceLabel;
  final int sourcePort;
  final String destLabel;
  final int destPort;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Flexible(child: _endpoint(colors, sourceLabel, sourcePort, accent)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            PhosphorIconsFill.arrowRight,
            size: 11,
            color: colors.textTertiary,
          ),
        ),
        Flexible(
          child: _endpoint(colors, destLabel, destPort, colors.textTertiary),
        ),
      ],
    );
  }

  /// Two [Text]s rather than one span: the name of an end and its port are
  /// each read on their own, both by a screen reader and by the tests that
  /// assert which end is named first.
  Widget _endpoint(AppColors colors, String label, int port, Color labelColor) {
    final style = colors.uiSmall.copyWith(fontSize: 11);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        Text(':$port', style: style),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/port_forwarding_rule.dart';
import '../../providers/port_forwarding_provider.dart';
import '../ui/add_row_card.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/empty_state.dart';
import '../ui/section_header.dart';
import 'port_forwarding_rule_sheet.dart';
import 'port_forwarding_rule_tile.dart';

class TunnelsPanel extends ConsumerStatefulWidget {
  const TunnelsPanel({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<TunnelsPanel> createState() => _TunnelsPanelState();
}

/// Scrolls rather than sizing to content: a profile can carry more rules
/// than fit a sheet, and a `Column` that just grows overflows off-screen.
class _TunnelsPanelState extends ConsumerState<TunnelsPanel> {
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final pfState = ref.watch(portForwardingProvider(widget.sessionId));
    final entries = pfState.entries.values.toList()
      ..sort((a, b) => a.rule.createdAt.compareTo(b.rule.createdAt));

    final profileEntries = entries.where((e) => e.isFromProfile).toList();
    final adhocEntries = entries.where((e) => !e.isFromProfile).toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.portForwarding.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            if (entries.isEmpty)
              EmptyStateHint(
                icon: PhosphorIconsRegular.arrowsLeftRight,
                text: t.portForwarding.noRulesYet,
                padding: const EdgeInsets.only(bottom: 16),
              ),

            if (profileEntries.isNotEmpty) ...[
              SectionHeader(t.portForwarding.profileRules),
              const SizedBox(height: 10),
              _group(profileEntries, isFromProfile: true),
              const SizedBox(height: 20),
            ],

            if (adhocEntries.isNotEmpty) ...[
              SectionHeader(t.portForwarding.adhocTunnels),
              const SizedBox(height: 10),
              _group(adhocEntries, isFromProfile: false),
              const SizedBox(height: 20),
            ],

            AddRowCard(
              label: t.portForwarding.addTunnel,
              onTap: () => _showAddAdhocTunnel(t),
            ),
          ],
        ),
      ),
    );
  }

  /// One card per group rather than one per rule - a screen of individually
  /// framed rows reads as a wireframe, which is what [AppCard.fields] and
  /// [AppDivider] exist to avoid. A profile's rules are edited and deleted
  /// on the profile, not torn out of the session that happens to be
  /// running them, so those tiles get no tap handler.
  Widget _group(List<TunnelEntry> entries, {required bool isFromProfile}) {
    return AppCard.fields(
      children: [
        for (final (i, e) in entries.indexed) ...[
          if (i > 0) const AppDivider(),
          PortForwardingRuleTile(
            rule: e.rule,
            status: e.status,
            errorMessage: e.errorMessage,
            onToggle: () => _toggle(e, isFromProfile: isFromProfile),
            onTap: isFromProfile ? null : () => _editAdhocTunnel(e.rule),
            onDelete: isFromProfile ? null : () => _remove(e),
          ),
        ],
      ],
    );
  }

  void _toggle(TunnelEntry entry, {required bool isFromProfile}) {
    final notifier = ref.read(
      portForwardingProvider(widget.sessionId).notifier,
    );
    if (entry.status == TunnelStatus.active) {
      notifier.stopTunnel(entry.rule.id);
    } else if (entry.status == TunnelStatus.idle ||
        entry.status == TunnelStatus.error) {
      notifier.startTunnel(entry.rule, isFromProfile: isFromProfile);
    }
  }

  void _remove(TunnelEntry entry) {
    ref
        .read(portForwardingProvider(widget.sessionId).notifier)
        .removeAdhocTunnel(entry.rule.id);
  }

  Future<void> _editAdhocTunnel(PortForwardingRule rule) async {
    final t = Translations.of(context);
    final edited = await showPortForwardingRuleSheet(
      context: context,
      title: t.portForwarding.editRule,
      existing: rule,
    );
    if (edited == null || !mounted) return;
    await ref
        .read(portForwardingProvider(widget.sessionId).notifier)
        .updateAdhocTunnel(edited);
  }

  Future<void> _showAddAdhocTunnel(Translations t) async {
    final rule = await showPortForwardingRuleSheet(
      context: context,
      title: t.portForwarding.addTunnel,
    );
    if (rule == null || !mounted) return;
    final notifier = ref.read(
      portForwardingProvider(widget.sessionId).notifier,
    );
    notifier.addAdhocTunnel(rule);
    await notifier.startTunnel(rule, isFromProfile: false);
  }
}

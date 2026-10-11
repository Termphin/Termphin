import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../i18n/strings.g.dart';
import '../../models/port_forwarding_rule.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_form_field.dart';
import '../ui/app_sheet.dart';
import '../ui/large_title_scaffold.dart';
import '../ui/section_header.dart';
import '../ui/two_line_label.dart';

const _uuid = Uuid();

/// Opens the editor for [existing], or for a new rule when it is null.
///
/// An edited rule keeps its id and creation time, so it lands back in the
/// list where it was rather than as a second, near-identical entry.
Future<PortForwardingRule?> showPortForwardingRuleSheet({
  required BuildContext context,
  required String title,
  PortForwardingRule? existing,
}) {
  return pushAppForm<PortForwardingRule>(
    context,
    builder: (_) => _PortForwardingRuleScreen(title: title, existing: existing),
  );
}

class _PortForwardingRuleScreen extends StatefulWidget {
  const _PortForwardingRuleScreen({required this.title, this.existing});

  final String title;
  final PortForwardingRule? existing;

  @override
  State<_PortForwardingRuleScreen> createState() =>
      _PortForwardingRuleScreenState();
}

/// The two ports are what the route preview reads, so every keystroke in
/// them has to trigger a rebuild - the host fields do not.
class _PortForwardingRuleScreenState extends State<_PortForwardingRuleScreen> {
  late ForwardType _type;
  late final TextEditingController _localPortCtrl;
  late final TextEditingController _remotePortCtrl;
  late final TextEditingController _remoteHostCtrl;
  late final TextEditingController _localHostCtrl;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? ForwardType.local;
    _localPortCtrl = TextEditingController(
      text: existing == null ? '' : '${existing.localPort}',
    );
    _remotePortCtrl = TextEditingController(
      text: existing == null ? '' : '${existing.remotePort}',
    );
    _remoteHostCtrl = TextEditingController(
      text: existing?.remoteHost ?? 'localhost',
    );
    _localHostCtrl = TextEditingController(
      text: existing?.localHost ?? 'localhost',
    );
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
  }

  @override
  void dispose() {
    _localPortCtrl.dispose();
    _remotePortCtrl.dispose();
    _remoteHostCtrl.dispose();
    _localHostCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  int? _port(TextEditingController c) {
    final value = int.tryParse(c.text.trim());
    if (value == null || value <= 0 || value > 65535) return null;
    return value;
  }

  bool get _canSave =>
      _port(_localPortCtrl) != null && _port(_remotePortCtrl) != null;

  String _hostOr(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? 'localhost' : value;
  }

  void _save() {
    final localPort = _port(_localPortCtrl);
    final remotePort = _port(_remotePortCtrl);
    if (localPort == null || remotePort == null) return;

    final isLocal = _type == ForwardType.local;
    final existing = widget.existing;
    Navigator.of(context).pop(
      PortForwardingRule(
        id: existing?.id ?? _uuid.v4(),
        type: _type,
        localPort: localPort,
        remoteHost: isLocal ? _hostOr(_remoteHostCtrl) : 'localhost',
        remotePort: remotePort,
        localHost: isLocal ? 'localhost' : _hostOr(_localHostCtrl),
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isLocal = _type == ForwardType.local;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: IconButton(
          tooltip: t.common.close,
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _canSave ? _save : null,
              child: Text(
                t.common.save,
                style: TextStyle(
                  color: _canSave
                      ? context.colors.primary
                      : context.colors.textTertiary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40).add(gutter),
            children: [
              SectionHeader(
                t.portForwarding.modeSection,
                hint: t.portForwarding.modeQuestion,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ModeOptionCard(
                      icon: PhosphorIconsFill.deviceMobile,
                      label: t.portForwarding.modeOptionDevice,
                      subtitle: t.portForwarding.modeOptionDeviceSubtitle,
                      selected: isLocal,
                      onTap: () => setState(() => _type = ForwardType.local),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeOptionCard(
                      icon: PhosphorIconsFill.globe,
                      label: t.portForwarding.modeOptionServer,
                      subtitle: t.portForwarding.modeOptionServerSubtitle,
                      selected: !isLocal,
                      onTap: () => setState(() => _type = ForwardType.remote),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isLocal
                    ? t.portForwarding.localForwardDescription
                    : t.portForwarding.remoteForwardDescription,
                style: context.colors.uiSmall.copyWith(
                  color: context.colors.textTertiary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 24),
              SectionHeader(t.portForwarding.previewSection),
              const SizedBox(height: 10),
              _RoutePreview(
                type: _type,
                localPort: _localPortCtrl.text.trim(),
                remotePort: _remotePortCtrl.text.trim(),
              ),

              const SizedBox(height: 24),
              SectionHeader(t.portForwarding.detailsSection),
              const SizedBox(height: 10),
              AppFormField(
                controller: _nameCtrl,
                label: t.portForwarding.name,
                hint: t.common.optional,
                icon: PhosphorIconsFill.tag,
              ),
              const SizedBox(height: 10),

              if (isLocal) ...[
                AppFormField(
                  controller: _localPortCtrl,
                  label: t.portForwarding.localPort,
                  hint: t.portForwarding.localPortHint,
                  icon: PhosphorIconsFill.deviceMobile,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                AppFormField(
                  controller: _remoteHostCtrl,
                  label: t.portForwarding.remoteHost,
                  hint: t.portForwarding.remoteHostHint,
                  icon: PhosphorIconsFill.globe,
                ),
                const SizedBox(height: 10),
                AppFormField(
                  controller: _remotePortCtrl,
                  label: t.portForwarding.remotePort,
                  hint: t.portForwarding.remotePortHint,
                  icon: PhosphorIconsFill.plugsConnected,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  action: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                AppFormField(
                  controller: _remotePortCtrl,
                  label: t.portForwarding.remotePortLabel,
                  hint: t.portForwarding.remotePortLabelHint,
                  icon: PhosphorIconsFill.globe,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                AppFormField(
                  controller: _localHostCtrl,
                  label: t.portForwarding.localHostLabel,
                  hint: t.portForwarding.localHostLabelHint,
                  icon: PhosphorIconsFill.deviceMobile,
                ),
                const SizedBox(height: 10),
                AppFormField(
                  controller: _localPortCtrl,
                  label: t.portForwarding.localPortTargetLabel,
                  hint: t.portForwarding.localPortTargetHint,
                  icon: PhosphorIconsFill.plugsConnected,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  action: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the two direction choices. Sized off [TwoLineLabel] so the pair
/// stays the same height whichever subtitle wraps.
class _ModeOptionCard extends StatelessWidget {
  const _ModeOptionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: selected ? colors.primaryHighlight : colors.surfaceCard,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: AppTheme.interactiveDuration,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.primaryMuted : colors.surfaceBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? colors.primary : colors.textTertiary,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: colors.uiStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.primary : colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              TwoLineLabel(
                text: subtitle,
                style: colors.uiSmall.copyWith(
                  fontSize: 11,
                  height: 1.3,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which end listens and which end the traffic comes out of, filled in as
/// the two port fields are typed.
class _RoutePreview extends StatelessWidget {
  const _RoutePreview({
    required this.type,
    required this.localPort,
    required this.remotePort,
  });

  final ForwardType type;
  final String localPort;
  final String remotePort;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isLocal = type == ForwardType.local;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _Endpoint(
                label: isLocal
                    ? t.portForwarding.arrowDevice
                    : t.portForwarding.arrowServer,
                port: isLocal ? localPort : remotePort,
                highlight: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                PhosphorIconsFill.arrowRight,
                size: 16,
                color: context.colors.textTertiary,
              ),
            ),
            Expanded(
              child: _Endpoint(
                label: isLocal
                    ? t.portForwarding.arrowServer
                    : t.portForwarding.arrowDevice,
                port: isLocal ? remotePort : localPort,
                highlight: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.label,
    required this.port,
    required this.highlight,
  });

  final String label;
  final String port;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasPort = port.isNotEmpty;
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: colors.uiSmall.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: highlight ? colors.primary : colors.textTertiary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          hasPort ? ':$port' : ':----',
          textAlign: TextAlign.center,
          style: colors.monoStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: hasPort
                ? colors.textPrimary
                : colors.textTertiary.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

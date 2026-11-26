import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/groups_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/relay_keys_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/push/machine_switches.dart';
import '../../services/push/notify_prefs_store.dart';
import '../../services/push/push_service.dart';
import '../../theme/theme.dart';
import '../profiles/machine_pro_button.dart';
import '../profiles/profile_avatar.dart';
import '../ui/app_badge.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_notifications.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// How many machines a list shows before "Show all".
const kProMachinesShown = 3;

/// The machines with [feature] on, in the order they are listed: by name.
List<SshProfile> machinesWith(
  MachineFeature feature,
  Iterable<SshProfile> profiles, {
  required Map<String, MachineSwitchChange> pending,
  required Iterable<RelayServer> keys,
}) => [
  for (final profile in profiles)
    if (switch (feature) {
      MachineFeature.notifications => machineSwitchesFor(
        profile.id,
        pending: pending,
        keys: keys,
        legacyNotify: profile.serverNotifications,
      ).notify,
      MachineFeature.live => machineSwitchesFor(
        profile.id,
        pending: pending,
        keys: keys,
      ).live,
    })
      profile,
]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// The name a phone or tablet is listed under, by its platform and kind. A
/// device with no kind, from an app that predates them, counts as a phone.
String notifyDeviceName(Translations t, NotifyDestination device) {
  final p = t.serversPanel;
  final tablet = device.kind == NotifyDeviceKind.tablet;
  if (device.platform == 'ios') return tablet ? p.ipad : p.iphone;
  return tablet ? p.androidTablet : p.androidPhone;
}

/// The icon a phone or tablet is listed with.
IconData notifyDeviceIcon(NotifyDestination device) =>
    device.kind == NotifyDeviceKind.tablet
    ? PhosphorIconsRegular.deviceTablet
    : PhosphorIconsRegular.deviceMobile;

/// The machines with [feature] on - only those: a machine is switched on
/// from the bell beside its menu in the list of machines - three at first
/// and the rest on request, each with a switch to turn it off. One still
/// waiting for its next connect says so.
class ProMachinesList extends ConsumerStatefulWidget {
  const ProMachinesList({super.key, required this.feature});

  final MachineFeature feature;

  @override
  ConsumerState<ProMachinesList> createState() => _ProMachinesListState();
}

class _ProMachinesListState extends ConsumerState<ProMachinesList> {
  bool _all = false;
  final _busy = <String>{};

  Future<void> _off(SshProfile profile) async {
    setState(() => _busy.add(profile.id));
    try {
      await switchMachine(context, ref, profile, switch (widget.feature) {
        MachineFeature.notifications => const MachineSwitchChange(
          notify: false,
        ),
        MachineFeature.live => const MachineSwitchChange(live: false),
      });
    } finally {
      if (mounted) setState(() => _busy.remove(profile.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountProvider) == null) return const SizedBox.shrink();
    final keys = ref.watch(relayKeysProvider).asData?.value ?? const [];
    final profiles = ref.watch(profilesProvider);
    return ValueListenableBuilder<Map<String, MachineSwitchChange>>(
      valueListenable: PushService.instance.pendingMachines,
      builder: (context, pending, _) => _list(
        machinesWith(widget.feature, profiles, pending: pending, keys: keys),
        pending,
        keys,
      ),
    );
  }

  Widget _list(
    List<SshProfile> machines,
    Map<String, MachineSwitchChange> pending,
    List<RelayServer> keys,
  ) {
    final t = Translations.of(context);
    final p = t.serversPanel;
    final anonymize = ref.watch(anonymizeProvider);
    final groups = ref.watch(profileGroupsProvider);
    final hint = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.colors.textSecondary);
    final shown = _all ? machines : machines.take(kProMachinesShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTheme.space16),
        SectionHeader(switch (widget.feature) {
          MachineFeature.notifications => p.notifyMachinesTitle,
          MachineFeature.live => p.liveMachinesTitle,
        }),
        const SizedBox(height: AppTheme.space8),
        if (machines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space4),
            child: Text(switch (widget.feature) {
              MachineFeature.notifications => p.notifyEmpty,
              MachineFeature.live => p.liveEmpty,
            }, style: hint),
          )
        else
          AppCard.fields(
            children: [
              for (final (index, profile) in shown.indexed) ...[
                if (index > 0) const AppDivider(),
                SettingsSwitchTile(
                  key: ValueKey('${widget.feature.name}-${profile.id}'),
                  leading: ProfileAvatar(
                    iconName: profile.iconName,
                    colorHex:
                        profile.colorHex ??
                        groups
                            .where((group) => group.name == profile.group)
                            .firstOrNull
                            ?.colorHex,
                    size: 36,
                  ),
                  title: anonymize
                      ? IdentityAnonymizer.name(profile.id)
                      : profile.name,
                  subtitle: pending.containsKey(profile.id)
                      ? p.pending
                      : p.ready,
                  value: true,
                  onChanged: _busy.contains(profile.id)
                      ? null
                      : (_) => unawaited(_off(profile)),
                ),
              ],
              if (!_all && machines.length > kProMachinesShown) ...[
                const AppDivider(),
                SettingsTile(
                  key: ValueKey('${widget.feature.name}ShowAll'),
                  title: p.showAll(n: machines.length),
                  trailing: SettingsTileTrailing.none,
                  onTap: () => setState(() => _all = true),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// The account's phones and tablets, each switched on or off for
/// notifications from any device - a computer too.
class ProDevicesList extends ConsumerStatefulWidget {
  const ProDevicesList({
    super.key,
    @visibleForTesting this.devices,
    @visibleForTesting this.ownId,
  });

  /// Stand in for [PushService] in tests.
  final Stream<List<NotifyDestination>>? devices;
  final String? ownId;

  @override
  ConsumerState<ProDevicesList> createState() => _ProDevicesListState();
}

class _ProDevicesListState extends ConsumerState<ProDevicesList> {
  late final _devices = widget.devices ?? PushService.instance.destinations();
  String? _ownId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOwnId());
  }

  Future<void> _loadOwnId() async {
    final id = widget.ownId ?? await PushService.instance.installId();
    if (mounted) setState(() => _ownId = id);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountProvider) == null) return const SizedBox.shrink();
    final t = Translations.of(context);
    final p = t.serversPanel;
    return StreamBuilder<List<NotifyDestination>>(
      stream: _devices,
      builder: (context, snapshot) {
        final devices = [
          ...?snapshot.data?.where((device) => device.id == _ownId),
          ...?snapshot.data?.where((device) => device.id != _ownId),
        ];
        if (devices.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppTheme.space16),
            SectionHeader(p.devicesTitle),
            const SizedBox(height: AppTheme.space8),
            AppCard.fields(
              children: [
                for (final (index, device) in devices.indexed) ...[
                  if (index > 0) const AppDivider(),
                  SettingsSwitchTile(
                    icon: notifyDeviceIcon(device),
                    title: notifyDeviceName(t, device),
                    titleTrailing: device.id == _ownId
                        ? Padding(
                            padding: const EdgeInsets.only(
                              left: AppTheme.space8,
                            ),
                            child: AppBadge(
                              p.thisDevice,
                              tone: BadgeTone.accent,
                            ),
                          )
                        : null,
                    value: device.enabled,
                    onChanged: (on) => unawaited(_switch(device, on)),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _switch(NotifyDestination device, bool on) async {
    try {
      await PushService.instance.setDestinationEnabled(device, on);
    } catch (_) {
      if (mounted) {
        AppNotifications.error(
          context,
          Translations.of(context).serversPanel.failed,
        );
      }
    }
  }
}

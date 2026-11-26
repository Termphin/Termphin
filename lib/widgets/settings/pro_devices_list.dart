import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../services/push/notify_prefs_store.dart';
import '../../services/push/push_service.dart';
import '../../theme/theme.dart';
import '../ui/app_badge.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_notifications.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

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

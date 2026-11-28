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
import '../ui/app_dropdown.dart';
import '../ui/app_notifications.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';
import '../ui/text_input_dialog.dart';

/// The name a phone or tablet is listed under: the one the user gave it,
/// otherwise its platform and kind ([defaultNotifyDeviceName]).
String notifyDeviceName(Translations t, NotifyDestination device) =>
    device.name ?? defaultNotifyDeviceName(t, device);

/// A phone or tablet's name by its platform and kind. A device with no kind,
/// from an app that predates them, counts as a phone.
String defaultNotifyDeviceName(Translations t, NotifyDestination device) {
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
    @visibleForTesting this.rename,
  });

  /// Stand in for [PushService] in tests.
  final Stream<List<NotifyDestination>>? devices;
  final String? ownId;
  final Future<void> Function(NotifyDestination device, String? name)? rename;

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
                  Row(
                    children: [
                      Expanded(
                        child: SettingsSwitchTile(
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
                          contentPadding: const EdgeInsets.only(
                            left: AppTheme.space14,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: AppTheme.space8),
                        child: AppActionDropdown<_DeviceAction>(
                          tooltip: p.deviceMore,
                          iconColor: context.colors.textSecondary,
                          width: 220,
                          onSelected: (action) =>
                              unawaited(_run(action, device)),
                          items: [
                            DropdownItem(
                              value: _DeviceAction.rename,
                              intrinsicHeight: true,
                              child: AppDropdownItem(
                                icon: PhosphorIconsRegular.pencilSimple,
                                label: p.renameDevice,
                              ),
                            ),
                            if (device.name != null)
                              DropdownItem(
                                value: _DeviceAction.resetName,
                                intrinsicHeight: true,
                                child: AppDropdownItem(
                                  icon: PhosphorIconsRegular
                                      .arrowCounterClockwise,
                                  label: p.resetDeviceName,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _run(_DeviceAction action, NotifyDestination device) async {
    final t = Translations.of(context);
    final String? name;
    switch (action) {
      case _DeviceAction.rename:
        final typed = await showTextInputDialog(
          context,
          title: t.serversPanel.renameDeviceTitle,
          confirmLabel: t.common.save,
          labelText: t.serversPanel.deviceNameLabel,
          hintText: defaultNotifyDeviceName(t, device),
          initialValue: device.name ?? '',
          validator: (value) =>
              (value?.trim().length ?? 0) > kNotifyDeviceNameMax
              ? t.serversPanel.deviceNameTooLong
              : null,
        );
        if (typed == null || !mounted) return;
        name = typed;
      case _DeviceAction.resetName:
        name = null;
    }
    try {
      await (widget.rename ?? PushService.instance.setDestinationName)(
        device,
        name,
      );
    } catch (_) {
      if (mounted) {
        AppNotifications.error(
          context,
          Translations.of(context).serversPanel.failed,
        );
      }
    }
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

/// What a phone or tablet's `⋮` menu offers.
enum _DeviceAction { rename, resetName }

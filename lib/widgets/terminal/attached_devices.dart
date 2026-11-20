import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/live_presence_provider.dart';
import '../../services/realtime/presence_device.dart';
import '../../theme/theme.dart';

/// The other devices attached to a session right now, as the session's agent
/// reports them: overlapping circles, one per device with the icon of its
/// kind, three at most and a count for the rest.
///
/// A circle names a device, never a person: what a device says about itself
/// is not verified - anyone with a shell on the server could claim to be
/// any device - so showing the account's picture would assert an identity
/// nothing has checked. A person's avatar belongs here once teams sign what
/// their devices say. This
/// device is left out - its own rows already say it is connected. Nothing
/// is drawn when no other device is attached or the server's state cannot
/// be read here.
///
/// A device's name is a machine name, so with [anonymizeProvider] on only
/// its kind is read out.
class AttachedDevices extends ConsumerWidget {
  const AttachedDevices({
    super.key,
    required this.profileId,
    required this.muxName,
  });

  final String profileId;
  final String? muxName;

  static const _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = muxName;
    if (name == null) return const SizedBox.shrink();
    final session = ref
        .watch(livePresenceProvider)[profileId]
        ?.sessions
        ?.where((session) => session.name == name)
        .firstOrNull;
    final self = ref.watch(thisDeviceIdProvider).value;
    final seen = <String>{};
    final devices = [
      for (final device in session?.devices ?? const <PresenceDevice>[])
        if (device.id != self && seen.add(device.id)) device,
    ];
    if (devices.isEmpty) return const SizedBox.shrink();

    final t = Translations.of(context);
    final anonymize = ref.watch(anonymizeProvider);
    final label = t.session.openOnDevices(
      devices: [
        for (final device in devices)
          anonymize ? _kindLabel(t, device.kind) : device.name,
      ].join(', '),
    );
    final circles = [
      for (final device in devices.take(_shown))
        _DeviceCircle(icon: iconFor(device.kind)),
      if (devices.length > _shown)
        _DeviceCircle(
          text: t.session.moreDevices(count: devices.length - _shown),
        ),
    ];
    const size = AppTheme.space24;
    const step = AppTheme.space24 - AppTheme.space8;

    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.space8),
      child: Tooltip(
        message: label,
        child: Semantics(
          key: const ValueKey('attachedDevices'),
          label: label,
          child: SizedBox(
            width: size + step * (circles.length - 1),
            height: size,
            child: Stack(
              children: [
                for (final (index, circle) in circles.indexed.toList().reversed)
                  Positioned(left: step * index, child: circle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData iconFor(PresenceDeviceKind kind) => switch (kind) {
    PresenceDeviceKind.phone => PhosphorIconsRegular.deviceMobile,
    PresenceDeviceKind.tablet => PhosphorIconsRegular.deviceTablet,
    PresenceDeviceKind.desktop => PhosphorIconsRegular.desktop,
  };

  static String _kindLabel(Translations t, PresenceDeviceKind kind) =>
      switch (kind) {
        PresenceDeviceKind.phone => t.session.deviceKindPhone,
        PresenceDeviceKind.tablet => t.session.deviceKindTablet,
        PresenceDeviceKind.desktop => t.session.deviceKindDesktop,
      };
}

class _DeviceCircle extends StatelessWidget {
  const _DeviceCircle({this.icon, this.text});

  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: AppTheme.space24,
      height: AppTheme.space24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceOffset,
        shape: BoxShape.circle,
        border: Border.all(color: colors.backgroundPrimary, width: 2),
      ),
      child: icon != null
          ? Icon(icon, size: AppTheme.icon12, color: colors.textSecondary)
          : Text(
              text ?? '',
              style: colors.uiSmall.copyWith(color: colors.textSecondary),
            ),
    );
  }
}

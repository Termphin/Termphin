import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../providers/account_provider.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/relay_keys_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/pro/pro_service.dart';
import '../../services/push/machine_switches.dart';
import '../../services/push/push_service.dart';
import '../../theme/theme.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_notifications.dart';

/// Which of a machine's two switches a menu row flips.
enum MachineFeature { notifications, live }

/// Flips one of a machine's switches the way the user asked from its card,
/// then says how it went: set up now, or on the next connect when the quick
/// one did not reach the machine. Shared by the card's bell and the lists in
/// Termphin Pro.
///
/// Notifications also go into the machine's own setting from before the
/// bell (`serverNotifications`), which syncs: a device still on an earlier
/// version decides by it whether the server stays quiet, so it does not
/// switch them back on.
Future<void> switchMachine(
  BuildContext context,
  WidgetRef ref,
  SshProfile profile,
  MachineSwitchChange change,
) async {
  final p = Translations.of(context).serversPanel;
  final name = ref.read(anonymizeProvider)
      ? IdentityAnonymizer.name(profile.id)
      : relayLabelFor(profile);
  final notify = change.notify;
  if (notify != null && !profile.isLocal) {
    await ref
        .read(profilesProvider.notifier)
        .setServerNotifications(profile.id, notify);
  }
  final done = await PushService.instance.setMachine(
    profile,
    change,
    manager: ref.read(sshSessionManagerProvider),
  );
  if (!context.mounted) return;
  if (done) {
    AppNotifications.success(context, p.setUp(name: name));
  } else {
    AppNotifications.info(context, p.notReached(name: name));
  }
}

/// The bell beside a machine's menu: what Termphin Pro does for it -
/// notifications, live status, each on or off - in a menu of its own. Lit
/// while either is on. Each change counts at once and is set up on the
/// machine over a quick connection, or on its next connect when that one
/// does not get through. Nothing without Pro or signed out.
class MachineProButton extends ConsumerStatefulWidget {
  const MachineProButton({
    super.key,
    required this.profile,
    @visibleForTesting this.pro,
  });

  final SshProfile profile;

  /// Stands in for [ProService.active] in tests.
  final ValueListenable<bool>? pro;

  @override
  ConsumerState<MachineProButton> createState() => _MachineProButtonState();
}

class _MachineProButtonState extends ConsumerState<MachineProButton> {
  bool _busy = false;

  Future<void> _flip(MachineFeature feature, MachineSwitches current) async {
    final change = switch (feature) {
      MachineFeature.notifications => flipOf(current, notify: true),
      MachineFeature.live => flipOf(current, live: true),
    };
    setState(() => _busy = true);
    try {
      await switchMachine(context, ref, widget.profile, change);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountProvider) == null) return const SizedBox.shrink();
    final keys = ref.watch(relayKeysProvider).asData?.value ?? const [];
    return ValueListenableBuilder<bool>(
      valueListenable: widget.pro ?? ProService.instance.active,
      builder: (context, pro, _) {
        if (!pro) return const SizedBox.shrink();
        return ValueListenableBuilder<Map<String, MachineSwitchChange>>(
          valueListenable: PushService.instance.pendingMachines,
          builder: (context, pending, _) {
            final current = machineSwitchesFor(
              relayProfileIdFor(widget.profile),
              pending: pending,
              keys: keys,
              legacyNotify: widget.profile.serverNotifications,
            );
            return _button(context, current);
          },
        );
      },
    );
  }

  Widget _button(BuildContext context, MachineSwitches current) {
    final p = Translations.of(context).serversPanel;
    final colors = context.colors;
    if (_busy) {
      return const SizedBox(
        width: AppTheme.space40,
        height: AppTheme.space40,
        child: Center(
          child: SizedBox.square(
            dimension: AppTheme.icon16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    DropdownItem<MachineFeature> item(
      MachineFeature feature,
      IconData icon,
      String label,
      bool on,
    ) => DropdownItem(
      value: feature,
      intrinsicHeight: true,
      child: AppDropdownItem(icon: icon, label: label, selected: on),
    );
    return AppActionDropdown<MachineFeature>(
      key: ValueKey('machinePro-${widget.profile.id}'),
      tooltip: p.buttonTooltip,
      icon: current.any
          ? PhosphorIconsFill.bellSimple
          : PhosphorIconsRegular.bellSimple,
      iconSize: AppTheme.icon18,
      iconColor: current.any ? colors.primary : colors.textTertiary,
      buttonSize: AppTheme.space40,
      width: 220,
      items: [
        item(
          MachineFeature.notifications,
          PhosphorIconsRegular.bellRinging,
          p.notifications,
          current.notify,
        ),
        item(
          MachineFeature.live,
          PhosphorIconsRegular.pulse,
          p.live,
          current.live,
        ),
      ],
      onSelected: (feature) => unawaited(_flip(feature, current)),
    );
  }
}

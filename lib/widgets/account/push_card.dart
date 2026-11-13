import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/ssh_session_manager_provider.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/push/push_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_notifications.dart';
import '../ui/settings_tile.dart';

/// Push notifications, on the account screen: on or off for this phone, and
/// a row per connected machine to give it a relay key.
class PushCard extends ConsumerStatefulWidget {
  const PushCard({super.key});

  @override
  ConsumerState<PushCard> createState() => _PushCardState();
}

class _PushCardState extends ConsumerState<PushCard> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await PushService.instance.enabled;
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _toggle(bool on) async {
    final t = Translations.of(context);
    setState(() => _busy = true);
    try {
      if (on) {
        final granted = await PushService.instance.enable();
        if (!granted && mounted) {
          AppNotifications.error(context, t.account.push.denied);
        }
      } else {
        await PushService.instance.disable();
      }
    } catch (_) {
      if (mounted) AppNotifications.error(context, t.account.push.failed);
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _install(String sessionId, String name) async {
    final t = Translations.of(context);
    setState(() => _busy = true);
    try {
      await PushService.instance.installOnServer(
        manager: ref.read(sshSessionManagerProvider),
        sessionId: sessionId,
        label: name,
      );
      if (mounted) {
        AppNotifications.success(context, t.account.push.installed(name: name));
      }
    } catch (_) {
      if (mounted) AppNotifications.error(context, t.account.push.failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final p = t.account.push;
    final text = Theme.of(context).textTheme;
    final anonymize = ref.watch(anonymizeProvider);
    final manager = ref.watch(sshSessionManagerProvider);
    final machines = <String, (String, String)>{};
    for (final session in manager.activeSessions) {
      if (session.dropped || session.sshService == null) continue;
      final name = anonymize
          ? IdentityAnonymizer.name(session.profile.id)
          : session.profile.name;
      machines.putIfAbsent(session.profile.id, () => (session.id, name));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space14,
              AppTheme.space14,
              AppTheme.space14,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title, style: text.titleMedium),
                const SizedBox(height: AppTheme.space6),
                Text(
                  p.body,
                  style: text.bodyMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SettingsSwitchTile(
            title: p.thisPhone,
            value: _enabled,
            onChanged: _busy ? null : _toggle,
          ),
          if (_enabled) ...[
            if (machines.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space14,
                  0,
                  AppTheme.space14,
                  AppTheme.space14,
                ),
                child: Text(
                  p.noServers,
                  style: text.bodySmall?.copyWith(
                    color: context.colors.textTertiary,
                  ),
                ),
              )
            else
              for (final (sessionId, name) in machines.values)
                SettingsTile(
                  icon: PhosphorIconsRegular.hardDrives,
                  title: p.serverRow(name: name),
                  trailing: SettingsTileTrailing.none,
                  onTap: _busy ? null : () => _install(sessionId, name),
                ),
          ],
        ],
      ),
    );
  }
}

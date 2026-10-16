import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../screens/settings/known_hosts_screen.dart';
import '../../services/security/lock_service.dart';
import '../../services/settings/lock_settings.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_notifications.dart';
import '../ui/confirm_dialog.dart';
import '../ui/section_header.dart';
import '../ui/settings_controls.dart';
import '../ui/settings_tile.dart';
import 'pin_setup_dialog.dart';

/// Security section: the PIN lock, biometric unlock, its timeout and the
/// known hosts list.
class SecuritySettingsSection extends StatefulWidget {
  const SecuritySettingsSection({super.key});

  @override
  State<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState extends State<SecuritySettingsSection> {
  bool _loaded = false;
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lockEnabled = await LockService.instance.isLockEnabled;
    final biometricEnabled = await LockService.instance.isBiometricEnabled;
    final biometricAvailable = await LockService.instance.isBiometricAvailable;
    if (!mounted) return;
    setState(() {
      _lockEnabled = lockEnabled;
      _biometricEnabled = biometricEnabled;
      _biometricAvailable = biometricAvailable;
      _loaded = true;
    });
  }

  Future<void> _onLockToggle(bool enabled) async {
    if (enabled) {
      final pin = await _showPinSetupDialog();
      if (pin == null) return;
      await LockService.instance.setPin(pin);
      setState(() => _lockEnabled = true);
    } else {
      final confirmed = await _showDisableLockDialog();
      if (!confirmed) return;
      await LockService.instance.disableLock();
      setState(() {
        _lockEnabled = false;
        _biometricEnabled = false;
      });
    }
  }

  Future<String?> _showPinSetupDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PinSetupDialog(),
    );
  }

  Future<bool> _showDisableLockDialog() async {
    final t = Translations.of(context);
    return showConfirmDialog(
      context,
      title: t.settings.disableLockTitle,
      message: t.settings.disableLockContent,
      confirmLabel: t.common.disable,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.security),
        const SizedBox(height: AppTheme.space10),
        AppCard.fields(
          children: [
            SettingsSwitchTile(
              title: t.settings.pinLock,
              subtitle: _lockEnabled
                  ? t.settings.pinLockEnabled
                  : t.settings.pinLockDisabled,
              value: _lockEnabled,
              onChanged: _onLockToggle,
            ),
            const AppDivider(),
            SettingsSwitchTile(
              title: t.settings.biometricUnlock,
              subtitle: !_lockEnabled
                  ? t.settings.enablePinFirst
                  : _biometricAvailable
                  ? t.settings.biometricSubtitle
                  : t.settings.biometricUnavailable,
              value: _biometricEnabled,
              onChanged: (_lockEnabled && _biometricAvailable)
                  ? (v) async {
                      await LockService.instance.setBiometricEnabled(v);
                      setState(() => _biometricEnabled = v);
                    }
                  : !_lockEnabled
                  ? (_) {
                      AppNotifications.info(context, t.settings.enablePinFirst);
                    }
                  : null,
            ),
            if (_lockEnabled) ...[
              const AppDivider(),
              Padding(
                padding: const EdgeInsets.all(AppTheme.space14),
                child: ValueListenableBuilder<LockTimeout>(
                  valueListenable: lockTimeoutSetting,
                  builder: (context, timeout, _) =>
                      SettingsDropdownField<LockTimeout>(
                        key: const ValueKey('lockTimeoutRow'),
                        label: t.settings.lockAfter,
                        value: timeout,
                        labels: {
                          LockTimeout.immediately:
                              t.settings.lockAfterImmediately,
                          LockTimeout.seconds30: t.settings.lockAfter30s,
                          LockTimeout.minute1: t.settings.lockAfter1m,
                          LockTimeout.minutes5: t.settings.lockAfter5m,
                        },
                        onChanged: (timeout) =>
                            unawaited(lockTimeoutSetting.set(timeout)),
                      ),
                ),
              ),
              const AppDivider(),
              SettingsTile(
                title: t.settings.changePin,
                onTap: () async {
                  final pin = await _showPinSetupDialog();
                  if (pin != null) {
                    await LockService.instance.setPin(pin);
                  }
                },
              ),
            ],
            const AppDivider(),
            SettingsTile(
              title: t.settings.knownHosts,
              subtitle: t.settings.knownHostsSubtitle,
              destination: () => const KnownHostsScreen(),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/platform/foreground_notification_service.dart';
import '../../services/ssh/local_network_permission.dart';
import '../../services/ssh/ssh_session_manager.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ssh/remote_agent_info_sheet.dart';
import '../ui/app_card.dart';
import '../ui/permission_tile.dart';
import '../ui/section_header.dart';
import '../ui/settings_tile.dart';

/// Connection section: the remote agent switch and the system permissions it
/// and the foreground service depend on.
class ConnectionSettingsSection extends StatefulWidget {
  const ConnectionSettingsSection({super.key});

  @override
  State<ConnectionSettingsSection> createState() =>
      _ConnectionSettingsSectionState();
}

class _ConnectionSettingsSectionState extends State<ConnectionSettingsSection>
    with WidgetsBindingObserver {
  bool _loaded = false;
  bool _remoteAgentEnabled = true;
  bool _notificationsGranted = false;
  bool _batteryUnrestricted = false;

  /// Only Android 17 and up gates local traffic, so on anything older the row
  /// describes a restriction that is not there.
  bool _localNetworkEnforced = false;
  bool _localNetworkGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from a system settings screen is the only signal that either
  /// permission may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSystemPermissions());
    }
  }

  Future<void> _load() async {
    final remoteAgentEnabled = remoteAgentSetting.value;
    final background = ForegroundNotificationService.instance;
    final batteryUnrestricted = await background.isIgnoringBatteryOptimizations;
    final notificationsGranted = await background.hasNotificationPermission;
    final localNetwork = LocalNetworkPermission.instance;
    final localNetworkEnforced = await localNetwork.isEnforced;
    final localNetworkGranted = await localNetwork.isGranted;
    if (!mounted) return;
    setState(() {
      _remoteAgentEnabled = remoteAgentEnabled;
      _batteryUnrestricted = batteryUnrestricted;
      _notificationsGranted = notificationsGranted;
      _localNetworkEnforced = localNetworkEnforced;
      _localNetworkGranted = localNetworkGranted;
      _loaded = true;
    });
  }

  Future<void> _onRemoteAgentToggle(bool enabled) async {
    setState(() => _remoteAgentEnabled = enabled);
    await remoteAgentSetting.set(enabled);
  }

  /// Both of these are system-owned and answer nothing back, so their state is
  /// re-read rather than assumed - and again on resume, since the user may
  /// have changed it on the system screen this opened.
  Future<void> _onBatteryOptimizationTap() async {
    await ForegroundNotificationService.instance
        .requestIgnoreBatteryOptimization();
    await _refreshSystemPermissions();
  }

  Future<void> _onNotificationsTap() async {
    final background = ForegroundNotificationService.instance;
    if (_notificationsGranted) {
      await background.openNotificationSettings();
    } else {
      await background.requestNotificationPermission();
    }
    await _refreshSystemPermissions();
  }

  /// A refusal the system will not re-prompt for leaves the app's settings
  /// page as the only way in, the same as the notification permission above.
  Future<void> _onLocalNetworkTap() async {
    final localNetwork = LocalNetworkPermission.instance;
    if (_localNetworkGranted) {
      await localNetwork.openAppSettings();
    } else {
      final result = await localNetwork.request();
      if (result == LocalNetworkPermissionResult.permanentlyDenied) {
        await localNetwork.openAppSettings();
      }
    }
    await _refreshSystemPermissions();
  }

  Future<void> _refreshSystemPermissions() async {
    final background = ForegroundNotificationService.instance;
    final batteryUnrestricted = await background.isIgnoringBatteryOptimizations;
    final notificationsGranted = await background.hasNotificationPermission;
    final localNetworkGranted = await LocalNetworkPermission.instance.isGranted;
    if (!mounted) return;
    setState(() {
      _batteryUnrestricted = batteryUnrestricted;
      _notificationsGranted = notificationsGranted;
      _localNetworkGranted = localNetworkGranted;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final t = Translations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(t.settings.connection),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              SettingsSwitchTile(
                title: t.settings.remoteAgentToggle,
                subtitle: t.settings.remoteAgentToggleSubtitle,
                value: _remoteAgentEnabled,
                onChanged: _onRemoteAgentToggle,
              ),
              const Divider(height: 1),
              SettingsTile(
                icon: PhosphorIconsRegular.shieldCheck,
                iconColor: context.colors.primary,
                title: t.settings.remoteAgentHowItWorks,
                subtitle: t.settings.remoteAgentHowItWorksSubtitle,
                onTap: () => showRemoteAgentInfoSheet(context),
              ),
              if (isIOSPlatform) ...[
                const Divider(height: 1),
                SettingsTile(
                  icon: PhosphorIconsRegular.moon,
                  iconColor: context.colors.textTertiary,
                  title: t.settings.backgroundSuspended,
                  subtitle: t.settings.backgroundSuspendedSubtitle,
                  trailing: SettingsTileTrailing.none,
                ),
              ],
              if (isAndroidPlatform) ...[
                const Divider(height: 1),
                PermissionTile(
                  leading: Icon(
                    _batteryUnrestricted
                        ? PhosphorIconsRegular.batteryCharging
                        : PhosphorIconsRegular.batteryWarning,
                    color: _batteryUnrestricted
                        ? context.colors.primary
                        : context.colors.warning,
                  ),
                  title: t.settings.batteryUnrestricted,
                  subtitle: t.settings.batteryUnrestrictedSubtitle,
                  granted: _batteryUnrestricted,
                  onTap: _onBatteryOptimizationTap,
                ),
              ],
              const Divider(height: 1),
              PermissionTile(
                leading: Icon(
                  _notificationsGranted
                      ? PhosphorIconsRegular.bell
                      : PhosphorIconsRegular.bellSlash,
                  color: _notificationsGranted
                      ? context.colors.primary
                      : context.colors.warning,
                ),
                title: t.settings.notificationsPermission,
                subtitle: t.settings.notificationsPermissionSubtitle,
                granted: _notificationsGranted,
                onTap: _onNotificationsTap,
              ),
              if (_localNetworkEnforced) ...[
                const Divider(height: 1),
                PermissionTile(
                  leading: Icon(
                    _localNetworkGranted
                        ? PhosphorIconsRegular.houseLine
                        : PhosphorIconsRegular.warningCircle,
                    color: _localNetworkGranted
                        ? context.colors.primary
                        : context.colors.warning,
                  ),
                  title: t.settings.localNetworkPermission,
                  subtitle: t.settings.localNetworkPermissionSubtitle,
                  granted: _localNetworkGranted,
                  onTap: _onLocalNetworkTap,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../providers/account_provider.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../screens/settings/notifications_settings_screen.dart';
import '../../screens/settings/relay_servers_screen.dart';
import '../../services/account/account_service.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/pro/pro_service.dart';
import '../../services/push/push_service.dart';
import '../../services/settings/setting.dart';
import '../../services/settings/terminal_settings.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../account/pro_feature_sheet.dart';
import '../ui/app_badge.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_notifications.dart';
import '../ui/motion_size.dart';
import '../ui/new_badge.dart';
import '../ui/segmented_switch.dart';
import '../ui/settings_tile.dart';

/// Every notification setting, for [NotificationsSettingsScreen]: what
/// programs in a session announce while the phone is connected (free), and
/// the same while it is not (Pro), with the servers that can reach the
/// account behind it.
///
/// Without Pro the closed-app switch carries a gold pill and opens the
/// paywall instead of turning on; a build without accounts shows only the
/// rest.
class NotificationsSettingsList extends ConsumerStatefulWidget {
  const NotificationsSettingsList({super.key, this.appVersion});

  /// For the "New" badges, which go by themselves in [kNotificationsNewUntil].
  final String? appVersion;

  @override
  ConsumerState<NotificationsSettingsList> createState() =>
      _NotificationsSettingsListState();
}

/// The first version notifications are no longer new in, for their badges
/// here and on the row in Settings.
const kNotificationsNewUntil = '1.17.0';

class _NotificationsSettingsListState
    extends ConsumerState<NotificationsSettingsList> {
  /// What the one "finishes or needs you" switch turns on and off together:
  /// a program's own request, a long command finishing, a program waiting.
  /// Kept as three settings underneath - the relay, backup and sync read
  /// them one by one.
  List<Setting<bool>> get _announcing => [
    terminalSettings.programNotifications,
    terminalSettings.finishedNotifications,
    terminalSettings.quietNotifications,
  ];

  Widget _noticeSwitch(
    Setting<bool> setting, {
    required String title,
    required String subtitle,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: setting,
      builder: (context, on, _) => Column(
        children: [
          const AppDivider(),
          SettingsSwitchTile(
            title: title,
            subtitle: subtitle,
            value: on,
            onChanged: (v) => unawaited(setting.set(v)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final accounts = AccountService.instance.available;
    return AppCard.fields(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge(_announcing),
          builder: (context, _) => SettingsSwitchTile(
            title: t.settings.commandNotifications,
            titleTrailing: NewBadge(
              appVersion: widget.appVersion,
              until: kNotificationsNewUntil,
            ),
            subtitle: t.settings.commandNotificationsSubtitle,
            value: _announcing.any((setting) => setting.value),
            onChanged: (on) {
              for (final setting in _announcing) {
                unawaited(setting.set(on));
              }
            },
          ),
        ),
        _noticeSwitch(
          terminalSettings.noticeLines,
          title: t.settings.noticeLines,
          subtitle: t.settings.noticeLinesSubtitle,
        ),
        const _OpenAppNotices(),
        if (accounts) NotifyWhenClosedTiles(appVersion: widget.appVersion),
      ],
    );
  }
}

/// What stands where the switch would be for someone without Pro: the way
/// to the plans, in Pro's gold. The row around it opens them.
class _SeePro extends StatelessWidget {
  const _SeePro();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Translations.of(context).settings.seePro,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.gold,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppTheme.space4),
        Icon(
          PhosphorIconsRegular.caretRight,
          size: AppTheme.icon16,
          color: colors.gold,
        ),
      ],
    );
  }
}

/// Whether a session that is not on screen notifies while Termphin is open,
/// and under it - only while it does - whether as the app's own card or as
/// the system's notification.
class _OpenAppNotices extends StatelessWidget {
  const _OpenAppNotices();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final enabled = terminalSettings.openAppNotices;
    final style = terminalSettings.openAppNoticeStyle;
    return ListenableBuilder(
      listenable: Listenable.merge([enabled, style]),
      builder: (context, _) => Column(
        children: [
          const AppDivider(),
          SettingsSwitchTile(
            title: t.settings.openAppNotices,
            subtitle: t.settings.openAppNoticesSubtitle,
            value: enabled.value,
            onChanged: (on) => unawaited(enabled.set(on)),
          ),
          MotionSize(
            duration: AppTheme.motionSlow,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: enabled.value
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space14,
                      0,
                      AppTheme.space14,
                      AppTheme.space14,
                    ),
                    child: SegmentedSwitch<String>(
                      segments: [
                        SwitchSegment(
                          value: kOpenAppNoticeInApp,
                          label: t.settings.openAppNoticeInApp,
                        ),
                        SwitchSegment(
                          value: kOpenAppNoticeSystem,
                          label: t.settings.openAppNoticeSystem,
                        ),
                      ],
                      selected: style.value,
                      onChanged: (value) => unawaited(style.set(value)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The Pro part of notifications: the switch that lets servers reach this
/// device with Termphin closed, and under it, once it is on, the servers
/// that can, or a way to renew while Pro has lapsed; last, the way to the
/// demo of how it works.
///
/// Without Pro the row carries a gold pill and opens the paywall instead of
/// turning on. In a card after other rows it starts with a divider;
/// [divided] off leaves it out where it comes first.
class NotifyWhenClosedTiles extends ConsumerStatefulWidget {
  const NotifyWhenClosedTiles({
    super.key,
    this.appVersion,
    this.divided = true,
    this.icon,
  });

  /// For the "New" badge, which goes by itself in [kNotificationsNewUntil].
  final String? appVersion;

  final bool divided;

  /// Drawn before the switch, where the rows around it have icons too.
  final IconData? icon;

  @override
  ConsumerState<NotifyWhenClosedTiles> createState() =>
      _NotifyWhenClosedTilesState();
}

class _NotifyWhenClosedTilesState extends ConsumerState<NotifyWhenClosedTiles> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    PushService.instance.enabledNotifier.value =
        await PushService.instance.enabled;
  }

  Future<void> _setPush(bool on, bool pro) async {
    if (on && !pro && !await ProService.instance.refresh()) {
      if (!mounted) return;
      await ProPaywallScreen.show(
        context,
        source: ProSource.settingsNotifications,
      );
      return;
    }
    if (!mounted) return;
    final t = Translations.of(context);
    setState(() => _busy = true);
    try {
      if (on) {
        final granted = await PushService.instance.enable();
        _notePush(granted ? 'granted' : 'denied');
        if (!granted && mounted) {
          AppNotifications.error(context, t.settings.notifyDenied);
        }
      } else {
        await PushService.instance.disable();
        unawaited(
          AnalyticsService.instance.capture(AnalyticsEvent.pushDisabled),
        );
      }
    } catch (_) {
      if (on) _notePush('failed');
      if (mounted) AppNotifications.error(context, t.settings.notifyFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notePush(String outcome) => unawaited(
    AnalyticsService.instance.capture(
      AnalyticsEvent.pushEnabled,
      properties: {AnalyticsProperty.outcome: outcome},
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final signedIn = ref.watch(accountProvider) != null;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ProService.instance.active,
        PushService.instance.enabledNotifier,
      ]),
      builder: (context, _) {
        final pro = ProService.instance.active.value;
        final enabled = PushService.instance.enabledNotifier.value;
        final paused = enabled && signedIn && !pro;
        if (!platformHas(PlatformFeature.receivesPush)) {
          return Column(
            children: [
              if (widget.divided) const AppDivider(),
              SettingsTile(
                key: const ValueKey('notifyOnPhoneNote'),
                icon: widget.icon,
                title: t.settings.notifyOnPhone,
                subtitle: t.settings.notifyOnPhoneSubtitle,
                trailing: SettingsTileTrailing.none,
              ),
            ],
          );
        }
        final title = t.settings.notifyWhenClosed;
        final subtitle = isIOSPlatform
            ? t.settings.notifyWhenClosedSubtitleIos
            : t.settings.notifyWhenClosedSubtitle;
        if (!pro && !paused) {
          void paywall() => ProPaywallScreen.show(
            context,
            source: ProSource.settingsNotifications,
          );
          return Column(
            children: [
              if (widget.divided) const AppDivider(),
              SettingsTile(
                icon: widget.icon,
                title: title,
                subtitle: subtitle,
                trailingWidget: const _SeePro(),
                onTap: paywall,
              ),
              const AppDivider(),
              const HowItWorksTile(feature: ProFeature.notifications),
            ],
          );
        }
        return Column(
          children: [
            if (widget.divided) const AppDivider(),
            SettingsSwitchTile(
              icon: widget.icon,
              title: title,
              subtitle: paused ? t.settings.notifyPaused : subtitle,
              titleTrailing: Padding(
                padding: const EdgeInsets.only(left: AppTheme.space8),
                child: paused
                    ? AppBadge(
                        t.account.sync.pausedBadge,
                        tone: BadgeTone.warning,
                      )
                    : NewBadge(
                        appVersion: widget.appVersion,
                        until: kNotificationsNewUntil,
                      ),
              ),
              value: enabled && signedIn,
              onChanged: _busy ? null : (on) => _setPush(on, pro),
            ),
            if (paused) ...[
              const AppDivider(),
              SettingsTile(
                title: t.account.sync.renew,
                onTap: () => ProPaywallScreen.show(
                  context,
                  source: ProSource.settingsNotifications,
                ),
              ),
            ],
            if (enabled && signedIn) ...[
              const AppDivider(),
              SettingsTile(
                title: t.settings.notifyServers,
                destination: () => const RelayServersScreen(),
              ),
            ],
            const AppDivider(),
            const HowItWorksTile(feature: ProFeature.notifications),
          ],
        );
      },
    );
  }
}

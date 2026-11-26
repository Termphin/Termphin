import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../services/account/account_service.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../../widgets/settings/notification_permission_note.dart';
import '../../widgets/settings/notifications_demo.dart';
import '../../widgets/settings/notifications_settings_section.dart';
import '../../widgets/settings/setting_reveal.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/info_note.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_navigator.dart';
import '../../widgets/ui/settings_tile.dart';
import '../pro/pro_features_screen.dart';

/// Every notification setting on a screen of its own, reached from the one
/// row Settings keeps for them.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key, this.appVersion, this.focus});

  /// For the "New" badges on the settings that are new.
  final String? appVersion;

  /// The title of a setting to scroll to and mark, when search opened it.
  final String? focus;

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      AnalyticsService.instance.screen(AnalyticsScreen.notificationsSettings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return LargeTitleScaffold(
      title: t.settings.notificationsSection,
      bodyBuilder: (context, scrollController, gutter) => SettingReveal(
        focus: widget.focus,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space16,
            0,
            AppTheme.space16,
            AppTheme.space32,
          ).add(gutter),
          children: [
            LargeTitleHeader(
              title: t.settings.notificationsSection,
              subtitle: t.settings.notificationsRowSubtitle,
              padding: const EdgeInsets.only(
                top: AppTheme.space24,
                bottom: AppTheme.space8,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            const NotificationsDemo(),
            const SizedBox(height: AppTheme.space20),
            const NotificationPermissionNote(),
            if (isIOSPlatform) ...[
              InfoNote(t.settings.iosNotificationsNote),
              const SizedBox(height: AppTheme.space16),
            ],
            NotificationsSettingsList(appVersion: widget.appVersion),
            if (AccountService.instance.available) const _MachinesLink(),
            if (isAndroidPlatform || isIOSPlatform) ...[
              const SizedBox(height: AppTheme.space20),
              const NotificationPermissionRow(),
            ],
          ],
        ),
      ),
    );
  }
}

/// The way from notifications to where machines and devices are switched,
/// Termphin Pro's own screen; shown signed in with Pro.
class _MachinesLink extends ConsumerWidget {
  const _MachinesLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(accountProvider) == null) return const SizedBox.shrink();
    final t = Translations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ProService.instance.active,
      builder: (context, pro, _) => pro
          ? Padding(
              padding: const EdgeInsets.only(top: AppTheme.space20),
              child: AppCard(
                child: SettingsTile(
                  key: const ValueKey('machinesLink'),
                  icon: PhosphorIconsRegular.hardDrives,
                  title: t.serversPanel.linkTitle,
                  subtitle: t.serversPanel.linkSubtitle,
                  onTap: () => pushAppPage<void>(
                    context,
                    title: t.proHub.title,
                    builder: (_) => const ProFeaturesScreen(),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

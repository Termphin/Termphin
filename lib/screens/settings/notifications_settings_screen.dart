import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../theme/theme.dart';
import '../../widgets/settings/notifications_demo.dart';
import '../../widgets/settings/notifications_settings_section.dart';
import '../../widgets/ui/large_title_scaffold.dart';

/// Every notification setting on a screen of its own, reached from the one
/// row Settings keeps for them.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key, this.appVersion});

  /// For the "New" badges on the settings that are new.
  final String? appVersion;

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
      bodyBuilder: (context, scrollController, gutter) => ListView(
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
          NotificationsSettingsList(appVersion: widget.appVersion),
        ],
      ),
    );
  }
}

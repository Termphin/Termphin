import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../../widgets/account/live_status_card.dart';
import '../../widgets/account/sync_card.dart';
import '../../widgets/settings/notifications_settings_section.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';

/// Everything Termphin Pro adds, in one place, for an account that has it:
/// notifications with Termphin closed, live status and sync - only what Pro
/// adds, so of notifications just the switch for when the app is closed,
/// not the free ones, and not the subscription, which the account page
/// keeps.
///
/// Each still lives where it always did - notifications in Settings, live
/// status and sync on the account page - and this screen shows the same
/// controls, so whoever wants to see what Pro gives them finds it all here.
/// Notifications and live status each carry a way to a short demo of how
/// they work.
class ProFeaturesScreen extends StatelessWidget {
  const ProFeaturesScreen({super.key, this.appVersion});

  /// For the "New" badge on the notifications switch.
  final String? appVersion;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final hub = t.proHub;
    return LargeTitleScaffold(
      title: hub.title,
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
            title: hub.title,
            subtitle: hub.rowSubtitle,
            padding: const EdgeInsets.only(
              top: AppTheme.space24,
              bottom: AppTheme.space8,
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          SectionHeader(hub.notificationsSection),
          const SizedBox(height: AppTheme.space8),
          AppCard.fields(
            children: [
              NotifyWhenClosedTiles(
                appVersion: appVersion,
                divided: false,
                icon: PhosphorIconsRegular.bellRinging,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space24),
          SectionHeader(hub.live),
          const SizedBox(height: AppTheme.space8),
          const LiveStatusCard(),
          const SizedBox(height: AppTheme.space24),
          SectionHeader(hub.sync),
          const SizedBox(height: AppTheme.space8),
          const SyncCard(),
        ],
      ),
    );
  }
}

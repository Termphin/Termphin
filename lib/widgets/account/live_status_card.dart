import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/settings_tile.dart';
import 'pro_feature_sheet.dart';
import 'sync_needed_tile.dart';

/// What live status is - on for every machine with Termphin Pro on, with
/// nothing to switch here - with a note when sync is off and the way to the
/// demo of how it works under it. Without Pro the row itself shows how live
/// status works, with the way to the paywall there.
class LiveStatusCard extends ConsumerWidget {
  const LiveStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    return AppCard(
      child: ListenableBuilder(
        listenable: ProService.instance.active,
        builder: (context, _) {
          if (!ProService.instance.active.value) {
            return SettingsTile(
              icon: PhosphorIconsRegular.pulse,
              title: t.account.live.title,
              subtitle: t.account.live.proHint,
              trailingWidget: const _SeePro(),
              onTap: () => showProFeatureSheet(context, ProFeature.liveStatus),
            );
          }
          return Column(
            children: [
              SettingsTile(
                icon: PhosphorIconsRegular.pulse,
                title: t.account.live.title,
                subtitle: t.account.live.subtitle,
                trailing: SettingsTileTrailing.none,
              ),
              SyncNeededTile(message: t.account.sync.needsSyncLive),
              const AppDivider(),
              const HowItWorksTile(feature: ProFeature.liveStatus),
            ],
          );
        },
      ),
    );
  }
}

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

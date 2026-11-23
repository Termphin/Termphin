import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../assistant/phin_demo.dart';
import '../pro/feature_demos.dart';
import '../ui/app_badge.dart';
import '../ui/app_sheet.dart';
import '../ui/modal_actions.dart';
import '../ui/settings_tile.dart';

/// The features a row in Settings can point at as needing Pro.
enum ProFeature {
  notifications(ProSource.settingsNotifications),
  liveStatus(ProSource.liveStatus),
  phin(ProSource.phin);

  const ProFeature(this.source);

  /// Where the user was when the paywall was opened from this feature.
  final ProSource source;
}

/// The gold "Pro" pill beside a row that needs Pro. Tapping it explains the
/// feature in a sheet and never opens the checkout; it is gone once the
/// account has Pro.
class ProFeatureChip extends StatelessWidget {
  const ProFeatureChip({super.key, required this.feature});

  final ProFeature feature;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ProService.instance.active,
      builder: (context, pro, _) {
        if (pro) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showProFeatureSheet(context, feature),
          child: AppBadge(t.account.pro.badge, tone: BadgeTone.pro),
        );
      },
    );
  }
}

/// Opens the explanation of [feature] as a sheet.
///
/// [offerPro] off leaves out the way to the paywall, for a sheet opened from
/// the paywall itself.
Future<void> showProFeatureSheet(
  BuildContext context,
  ProFeature feature, {
  bool offerPro = true,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => ProFeatureSheet(
      feature: feature,
      paywallContext: context,
      offerPro: offerPro,
    ),
  );
}

/// What a Pro feature does: shown working on a phone, then in two
/// sentences, with a way to the paywall for an account without Pro.
///
/// [paywallContext] is the screen the sheet was opened from: the sheet is
/// gone by the time the paywall opens, so the paywall is pushed from there.
class ProFeatureSheet extends StatelessWidget {
  const ProFeatureSheet({
    super.key,
    required this.feature,
    required this.paywallContext,
    this.offerPro = true,
  });

  final ProFeature feature;
  final BuildContext paywallContext;

  /// Whether an account without Pro is offered the way to the paywall.
  final bool offerPro;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = Theme.of(context).textTheme;
    final (title, body, demo) = switch (feature) {
      ProFeature.notifications => (
        t.proFeature.notificationsTitle,
        t.proFeature.notificationsBody,
        const FeatureDemo(kind: FeatureDemoKind.notifications) as Widget,
      ),
      ProFeature.liveStatus => (
        t.proFeature.liveTitle,
        t.proFeature.liveBody,
        const FeatureDemo(kind: FeatureDemoKind.live) as Widget,
      ),
      ProFeature.phin => (
        t.assistant.howTitle,
        t.assistant.howBody,
        const PhinDemo() as Widget,
      ),
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space16,
          AppTheme.space20,
          AppTheme.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: demo),
            const SizedBox(height: AppTheme.space20),
            Text(title, style: text.titleMedium),
            const SizedBox(height: AppTheme.space12),
            Text(
              body,
              style: text.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            if (offerPro && !ProService.instance.active.value) ...[
              const SizedBox(height: AppTheme.space24),
              ModalActions(
                primary: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppTheme.space48),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(
                      ProPaywallScreen.show(
                        paywallContext,
                        source: feature.source,
                      ),
                    );
                  },
                  child: Text(t.proFeature.seePro),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The row under a Pro feature's switch that opens its demo in the sheet.
class HowItWorksTile extends StatelessWidget {
  const HowItWorksTile({super.key, required this.feature});

  final ProFeature feature;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      key: ValueKey('howItWorks-${feature.name}'),
      icon: PhosphorIconsRegular.playCircle,
      title: Translations.of(context).proFeature.howItWorks,
      onTap: () => unawaited(showProFeatureSheet(context, feature)),
    );
  }
}

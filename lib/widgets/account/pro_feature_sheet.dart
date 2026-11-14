import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../models/pro_source.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../ui/app_badge.dart';
import '../ui/app_sheet.dart';

/// The features a row in Settings can point at as needing Pro.
enum ProFeature {
  notifications(ProSource.settingsNotifications);

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
Future<void> showProFeatureSheet(BuildContext context, ProFeature feature) {
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) =>
        ProFeatureSheet(feature: feature, paywallContext: context),
  );
}

/// What a Pro feature does, in two sentences, with a way to the paywall.
///
/// [paywallContext] is the screen the sheet was opened from: the sheet is
/// gone by the time the paywall opens, so the paywall is pushed from there.
class ProFeatureSheet extends StatelessWidget {
  const ProFeatureSheet({
    super.key,
    required this.feature,
    required this.paywallContext,
  });

  final ProFeature feature;
  final BuildContext paywallContext;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = Theme.of(context).textTheme;
    final (title, body) = switch (feature) {
      ProFeature.notifications => (
        t.proFeature.notificationsTitle,
        t.proFeature.notificationsBody,
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
            Text(title, style: text.titleMedium),
            const SizedBox(height: AppTheme.space12),
            Text(
              body,
              style: text.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.space20),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(
                  ProPaywallScreen.show(paywallContext, source: feature.source),
                );
              },
              child: Text(t.proFeature.seePro),
            ),
          ],
        ),
      ),
    );
  }
}

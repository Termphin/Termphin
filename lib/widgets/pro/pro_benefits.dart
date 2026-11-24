import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../account/pro_feature_sheet.dart';
import '../ui/app_badge.dart';

/// Everything Termphin Pro gives, in the order it is listed - the one list
/// the paywall, the Pro screen and the welcome all draw from, so a benefit
/// is added, renamed or reworded in one place.
///
/// A new value is a new row everywhere at once; the Pro screen switches over
/// these for each benefit's controls, so it does not build until it says
/// what the new one's are.
enum ProBenefit {
  phin(PhosphorIconsRegular.sparkle, demo: ProFeature.phin),
  notifications(
    PhosphorIconsRegular.bellRinging,
    demo: ProFeature.notifications,
  ),
  liveStatus(PhosphorIconsRegular.pulse, demo: ProFeature.liveStatus),
  sync(PhosphorIconsRegular.arrowsClockwise);

  const ProBenefit(this.icon, {this.demo});

  final IconData icon;

  /// The feature whose "how it works" demo shows this one, if there is one.
  final ProFeature? demo;

  String title(Translations t) {
    final p = t.account.pro.paywall;
    return switch (this) {
      phin => p.phinTitle,
      notifications => p.pushTitle,
      liveStatus => p.liveTitle,
      sync => p.syncTitle,
    };
  }

  String body(Translations t) {
    final p = t.account.pro.paywall;
    return switch (this) {
      phin => p.phinBody,
      notifications => p.pushBody,
      liveStatus => p.liveBody,
      sync => p.syncBody,
    };
  }

  /// A word beside the title, such as "Beta".
  String? badge(Translations t) => switch (this) {
    phin => t.assistant.beta,
    _ => null,
  };
}

/// One benefit as every list of them draws it: an icon, the title with its
/// badge, two lines on what it does, and [footer] under those.
class ProBenefitRow extends StatelessWidget {
  const ProBenefitRow({
    super.key,
    required this.benefit,
    this.iconColor,
    this.footer,
  });

  final ProBenefit benefit;

  /// Gold where Pro is already the account's, quieter on the paywall.
  final Color? iconColor;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final badge = benefit.badge(t);
    final footer = this.footer;
    return Row(
      key: ValueKey('proBenefit-${benefit.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          benefit.icon,
          size: AppTheme.icon20,
          color: iconColor ?? colors.gold,
        ),
        const SizedBox(width: AppTheme.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(benefit.title(t), style: text.titleSmall),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: AppTheme.space6),
                    AppBadge(badge, tone: BadgeTone.highlight),
                  ],
                ],
              ),
              const SizedBox(height: AppTheme.space2),
              Text(
                benefit.body(t),
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              ?footer,
            ],
          ),
        ),
      ],
    );
  }
}

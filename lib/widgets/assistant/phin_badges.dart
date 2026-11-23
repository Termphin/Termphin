import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../theme/theme.dart';
import '../account/pro_feature_sheet.dart';
import '../ui/app_badge.dart';

/// What goes beside Phin's name in settings: "Beta" while it is one, and
/// the gold "Pro" for an account without Pro, which explains Phin on tap.
class PhinBadges extends StatelessWidget {
  const PhinBadges({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: AppTheme.space8),
        AppBadge(
          Translations.of(context).assistant.beta,
          tone: BadgeTone.highlight,
        ),
        const SizedBox(width: AppTheme.space4),
        const ProFeatureChip(feature: ProFeature.phin),
      ],
    );
  }
}

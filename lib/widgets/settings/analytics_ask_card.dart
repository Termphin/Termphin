import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/analytics/analytics_service.dart';
import '../../theme/theme.dart';

/// The one time Termphin asks to share anonymous stats and crash reports: a
/// card over the home screen, put up by [AnalyticsService.maybeAsk] once the
/// app has been used for real. Both answers are the same size, so saying no
/// is as easy as saying yes - a choice nobody has to undo, and the only kind
/// of consent that counts. Not answering is a no; it is never asked again.
class AnalyticsAskCard extends StatelessWidget {
  const AnalyticsAskCard({super.key, required this.onAnswer});

  /// Records the answer: true to share, false not to.
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Material(
      color: colors.surfaceOffset,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: colors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: AppTheme.icon40,
                  height: AppTheme.icon40,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIconsRegular.chartLineUp,
                    color: colors.primary,
                    size: AppTheme.icon20,
                  ),
                ),
                const SizedBox(width: AppTheme.space12),
                Expanded(
                  child: Text(
                    t.analyticsConsent.askTitle,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space10),
            Text(
              t.analyticsConsent.askBody,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppTheme.space14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => onAnswer(false),
                    child: Text(t.analyticsConsent.askNo),
                  ),
                ),
                const SizedBox(width: AppTheme.space10),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => onAnswer(true),
                    child: Text(t.analyticsConsent.askYes),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

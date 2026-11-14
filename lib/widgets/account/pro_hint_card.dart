import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../screens/pro/pro_paywall_screen.dart';
import '../../services/pro/pro_hints.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';

/// The Pro hint on the machine list: one quiet line that says what Pro would
/// do, a small way to the paywall and a close button - compact enough to sit
/// above the machines without pushing them away. Nothing while no hint is
/// up.
class ProHintCard extends StatelessWidget {
  const ProHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<ProHint?>(
      valueListenable: ProHints.instance.current,
      builder: (context, hint, _) {
        if (hint == null) return const SizedBox.shrink();
        final label = switch (hint) {
          ProHint.longCommand => t.proHints.longCommand,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.space8),
          child: AppCard(
            padding: const EdgeInsets.only(
              left: AppTheme.space12,
              top: AppTheme.space2,
              bottom: AppTheme.space2,
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsFill.sparkle,
                  size: AppTheme.icon14,
                  color: colors.gold,
                ),
                const SizedBox(width: AppTheme.space8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    ProHints.instance.dismiss();
                    unawaited(
                      ProPaywallScreen.show(context, source: hint.source),
                    );
                  },
                  child: Text(t.proHints.action),
                ),
                IconButton(
                  tooltip: t.proHints.dismiss,
                  visualDensity: VisualDensity.compact,
                  onPressed: ProHints.instance.dismiss,
                  icon: Icon(
                    PhosphorIconsRegular.x,
                    size: AppTheme.icon14,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

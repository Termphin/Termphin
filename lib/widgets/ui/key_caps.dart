import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// Keys drawn as keys: each label in its own small raised cap, side by side,
/// as a keyboard shortcut is shown next to what it does. A thicker lower
/// edge reads as a key standing up.
class KeyCaps extends StatelessWidget {
  const KeyCaps(this.keys, {super.key});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, key) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: AppTheme.space2),
          Container(
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space4,
              vertical: AppTheme.space2,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.fieldFill,
              borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              border: Border(
                top: BorderSide(color: colors.surfaceBorderStrong),
                left: BorderSide(color: colors.surfaceBorderStrong),
                right: BorderSide(color: colors.surfaceBorderStrong),
                bottom: BorderSide(color: colors.surfaceBorderStrong, width: 2),
              ),
            ),
            child: Text(
              key,
              style: colors.uiSmall.copyWith(
                fontSize: AppTheme.font10,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

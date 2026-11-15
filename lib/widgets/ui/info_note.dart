import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// How loudly an [InfoNote] speaks.
enum InfoNoteTone {
  /// How something works: the accent's quiet tint, the one selections use.
  info,

  /// Something in the way that the user can fix, in the warning's tint.
  warning,
}

/// A short explanation set apart in a quiet tint, above the settings it
/// explains. Not an error: with [InfoNoteTone.warning] it points at
/// something to fix, and [action] names the fix that a tap on the note runs.
class InfoNote extends StatelessWidget {
  const InfoNote(
    this.text, {
    super.key,
    this.tone = InfoNoteTone.info,
    this.action,
    this.onTap,
  });

  final String text;
  final InfoNoteTone tone;

  /// The fix, shown under [text] in the tone's colour.
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final (background, border, accent, icon) = switch (tone) {
      InfoNoteTone.info => (
        colors.primaryHighlight,
        colors.primaryMuted,
        colors.primary,
        PhosphorIconsRegular.info,
      ),
      InfoNoteTone.warning => (
        colors.warningHighlight,
        colors.warning,
        colors.warning,
        PhosphorIconsRegular.warning,
      ),
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      side: BorderSide(color: border, width: AppTheme.hairline),
    );
    return Material(
      color: background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: AppTheme.icon20, color: accent),
              const SizedBox(width: AppTheme.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (action case final action?) ...[
                      const SizedBox(height: AppTheme.space8),
                      Text(
                        action,
                        style: textTheme.bodyMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

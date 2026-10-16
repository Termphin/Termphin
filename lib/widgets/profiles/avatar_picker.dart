import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import '../ui/app_card.dart';
import 'profile_avatar.dart';

/// Preview, icon grid and colour row for a machine's [ProfileAvatar].
///
/// Its own widget rather than a block inside the profile form, so the form
/// reads as the list of fields it is.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    required this.iconName,
    required this.colorHex,
    required this.onIconChanged,
    required this.onColorChanged,
  });

  final String? iconName;
  final String? colorHex;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<String> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final avatarColor = ProfileAvatarColor.forHex(colorHex);
    return AppCard(
      padding: const EdgeInsets.all(AppTheme.space14),
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Column(
        children: [
          ProfileAvatar(iconName: iconName, colorHex: colorHex, size: 56),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            alignment: WrapAlignment.center,
            children: ProfileAvatarData.icons.map((item) {
              final selected = (iconName ?? 'desktop') == item.id;
              return GestureDetector(
                onTap: () => onIconChanged(item.id),
                child: AnimatedContainer(
                  duration: AppTheme.interactiveDuration,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? avatarColor.color.withValues(alpha: 0.15)
                        : context.colors.surfaceOffset,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: selected
                        ? Border.all(
                            color: avatarColor.color.withValues(alpha: 0.5),
                            width: 1.5,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: ProfileAvatarGlyph(
                    iconName: item.id,
                    size: 21,
                    color: selected
                        ? avatarColor.color
                        : context.colors.textTertiary,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.space14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ProfileAvatarColor.colors.map((item) {
              final selected = (colorHex ?? '4DA3FF') == item.hex;
              return GestureDetector(
                onTap: () => onColorChanged(item.hex),
                child: AnimatedContainer(
                  duration: AppTheme.interactiveDuration,
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space4,
                  ),
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: ProfileAvatarColor.onSwatch,
                            width: 2.5,
                          )
                        : null,
                  ),
                  child: selected
                      ? const Icon(
                          PhosphorIconsRegular.check,
                          size: AppTheme.icon14,
                          color: ProfileAvatarColor.onSwatch,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

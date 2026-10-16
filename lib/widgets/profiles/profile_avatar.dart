import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/theme.dart';

class ProfileAvatarData {
  const ProfileAvatarData(this.id, this.assetName);

  final String id;
  final String assetName;

  String get assetPath => 'assets/icons/profile_avatars/$assetName.svg';

  static const List<ProfileAvatarData> icons = [
    ProfileAvatarData('desktop', 'desktop'),
    ProfileAvatarData('hardDrives', 'hard_drives'),
    ProfileAvatarData('cloud', 'cloud'),
    ProfileAvatarData('database', 'database'),
    ProfileAvatarData('globe', 'globe'),
    ProfileAvatarData('house', 'house'),
    ProfileAvatarData('terminal', 'terminal'),
    ProfileAvatarData('robot', 'robot'),
    ProfileAvatarData('lightning', 'lightning'),
    ProfileAvatarData('shieldCheck', 'shield_check'),
    ProfileAvatarData('gameController', 'game_controller'),
    ProfileAvatarData('cpu', 'cpu'),
  ];

  static String pathForName(String? name) {
    if (name == null) return icons.first.assetPath;
    return icons
        .firstWhere((i) => i.id == name, orElse: () => icons.first)
        .assetPath;
  }
}

class ProfileAvatarGlyph extends StatelessWidget {
  const ProfileAvatarGlyph({
    super.key,
    required this.iconName,
    required this.color,
    required this.size,
  });

  final String? iconName;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      ProfileAvatarData.pathForName(iconName),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

class ProfileAvatarColor {
  const ProfileAvatarColor(this.hex, this.color);
  final String hex;
  final Color color;

  Color get background => color.withValues(alpha: 0.15);

  /// The ring and check drawn on a selected swatch. The swatches are a fixed
  /// palette that does not follow the theme, so neither does this.
  static const Color onSwatch = AppTheme.avatarForeground;

  static List<ProfileAvatarColor> colors = [
    ProfileAvatarColor('4DA3FF', AppTheme.avatarPalette[0]),
    ProfileAvatarColor('4ADE80', AppTheme.avatarPalette[1]),
    ProfileAvatarColor('8B5CF6', AppTheme.avatarPalette[2]),
    ProfileAvatarColor('F59E0B', AppTheme.avatarPalette[3]),
    ProfileAvatarColor('F87171', AppTheme.avatarPalette[4]),
    ProfileAvatarColor('06B6D4', AppTheme.avatarPalette[5]),
    ProfileAvatarColor('F472B6', AppTheme.avatarPalette[6]),
  ];

  static ProfileAvatarColor forHex(String? hex) {
    if (hex == null) return colors.first;
    return colors.firstWhere((c) => c.hex == hex, orElse: () => colors.first);
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.iconName,
    required this.colorHex,
    this.isActive = false,
    this.size = 42,
  });

  final String? iconName;
  final String? colorHex;
  final bool isActive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarColor = ProfileAvatarColor.forHex(colorHex);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: avatarColor.background,
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [
                avatarColor.color.withValues(alpha: 0.08),
                avatarColor.color.withValues(alpha: 0.28),
              ],
            ),
            shape: BoxShape.circle,
            border: isActive
                ? Border.all(color: context.colors.success, width: 1.5)
                : Border.all(color: avatarColor.color.withValues(alpha: 0.28)),
          ),
          alignment: Alignment.center,
          child: ProfileAvatarGlyph(
            iconName: iconName,
            size: size * 0.52,
            color: avatarColor.color,
          ),
        ),
        if (isActive)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: context.colors.success,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.colors.backgroundPrimary,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../profiles/profile_avatar.dart';

class GroupDot extends StatelessWidget {
  const GroupDot({super.key, required this.colorHex, this.size = 8});

  final String? colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = colorHex != null
        ? ProfileAvatarColor.forHex(colorHex).color
        : context.colors.textTertiary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

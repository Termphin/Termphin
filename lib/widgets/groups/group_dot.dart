import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';
import '../profiles/profile_avatar.dart';

/// A group's colour as a small dot. A group nobody has coloured takes the
/// accent rather than grey, so every group heading carries some colour and
/// the default one does not look switched off.
class GroupDot extends StatelessWidget {
  const GroupDot({super.key, required this.colorHex, this.size = 8});

  final String? colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = colorHex != null
        ? ProfileAvatarColor.forHex(colorHex).color
        : context.colors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

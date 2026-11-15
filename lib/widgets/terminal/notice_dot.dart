import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// A dot on a session's avatar while it has a notification the user has not
/// seen yet, cut out of whatever is behind it by a ring in [ground] so it
/// reads on any avatar colour. It fades rather than pops, in both
/// directions.
class NoticeDot extends StatelessWidget {
  const NoticeDot({
    super.key,
    required this.visible,
    required this.ground,
    required this.child,
  });

  final bool visible;
  final Color ground;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -AppTheme.space2,
          right: -AppTheme.space2,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: AppTheme.motionSlow,
            child: Container(
              key: const ValueKey('noticeDot'),
              width: AppTheme.space10,
              height: AppTheme.space10,
              decoration: BoxDecoration(
                color: context.colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: ground, width: AppTheme.hairline * 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

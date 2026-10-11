import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_profile.dart';
import '../../theme/theme.dart';
import '../profiles/profile_avatar.dart';

/// Room the handle between two split panes takes up.
const kSplitDividerThickness = 10.0;

/// Height of the name bar over each pane of a stacked split.
const kSplitHeaderHeight = 30.0;

/// About as long as the system keyboard takes to slide in, so a stacked
/// split folds while it does.
const kSplitFoldDuration = Duration(milliseconds: 250);

/// Mirrors the drag feedback the old LongPressDraggable ghost used - a
/// lifted, bordered pill - so a dragged tab or split header looks lifted
/// instead of falling back to plain elevation.
Widget tabDragProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = Curves.easeOut.transform(animation.value);
      return Transform.scale(
        scale: 1 + 0.03 * t,
        child: Material(
          color: context.colors.backgroundPrimary.invisible,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          shadowColor: Colors.black.withValues(alpha: 0.35),
          elevation: 10 * t,
          child: child,
        ),
      );
    },
    child: child,
  );
}

/// The bar naming a pane of a stacked split, lit when that pane has focus.
class SplitPaneHeader extends StatelessWidget {
  const SplitPaneHeader({
    super.key,
    required this.profile,
    required this.label,
    required this.focused,
    required this.onTap,
  });

  final SshProfile profile;
  final String label;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.motionFast,
        height: kSplitHeaderHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: focused
            ? Color.alphaBlend(
                colors.primary.withValues(alpha: 0.14),
                background,
              )
            : background,
        child: Row(
          children: [
            ProfileAvatar(
              iconName: profile.iconName,
              colorHex: profile.colorHex,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                  color: focused ? colors.primary : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The handle between two split panes, dragged to share the room out
/// differently.
class SplitDivider extends StatelessWidget {
  const SplitDivider({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.onHeld,
  });

  final Axis axis;
  final ValueChanged<double> onDrag;

  /// Held down, the tab swipe must leave the pointer alone.
  final ValueChanged<bool> onHeld;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return Listener(
      onPointerDown: (_) => onHeld(true),
      onPointerUp: (_) => onHeld(false),
      onPointerCancel: (_) => onHeld(false),
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey('splitDivider'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: horizontal
              ? (details) => onDrag(details.delta.dx)
              : null,
          onVerticalDragUpdate: horizontal
              ? null
              : (details) => onDrag(details.delta.dy),
          child: Semantics(
            label: Translations.of(context).terminal.splitDivider,
            child: SizedBox(
              width: horizontal ? kSplitDividerThickness : null,
              height: horizontal ? null : kSplitDividerThickness,
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: Container(
                    width: horizontal ? 3 : 32,
                    height: horizontal ? 32 : 3,
                    decoration: BoxDecoration(
                      color: context.colors.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

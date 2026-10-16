import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// The square icon button of an inline bar - previous, next and close in the
/// terminal's search bar and the editor's find bar.
///
/// Both bars had a private copy that had already drifted on icon size and
/// tap target; this is the one they share. Disabled when [onPressed] is null.
class BarIconButton extends StatelessWidget {
  const BarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = AppTheme.icon16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  /// Small enough that three of these fit beside a field in a bar, still a
  /// comfortable target for a thumb.
  static const double _extent = 30;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: _extent, height: _extent),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: size),
    color: context.colors.textSecondary,
    onPressed: onPressed,
  );
}

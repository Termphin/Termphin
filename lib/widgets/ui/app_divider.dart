import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Hairline divider between rows inside an [AppCard]-style container.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.indent = 0});

  /// Left inset, e.g. to align under a leading icon/avatar in a list tile.
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Container(height: 1, color: context.colors.surfaceDivider),
  );
}

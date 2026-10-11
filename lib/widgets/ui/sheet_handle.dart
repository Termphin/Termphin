import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'app_sheet.dart';

/// The grab bar at the top of a bottom sheet.
///
/// Shared because three sheets had drawn their own identical 36x4 pill, which
/// is three places to miss when the colour or the spacing above it changes.
/// Nothing is dragged in a dialog, so there nothing is advertised.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, this.topPadding = 12});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    if (AppModalScope.isDialog(context)) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.surfaceBorder,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
        ),
      ),
    );
  }
}

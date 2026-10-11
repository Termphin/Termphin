import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// A card-shaped "add one more" row: plus icon, accent label.
///
/// Both places that list port forwarding rules drew their own out of a
/// [GestureDetector] and a [Container], which is two paddings and two font
/// sizes to keep in step, and neither gave the row a ripple. Borders follow
/// [AppCard] - a stroke in light, the surface step alone in dark.
class AddRowCard extends StatelessWidget {
  const AddRowCard({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: colors.surfaceCard,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: colors.isDark
                ? null
                : Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.plus, size: 18, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                label,
                style: colors.uiStyle.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

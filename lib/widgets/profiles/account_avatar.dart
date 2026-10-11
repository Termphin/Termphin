import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.email,
    this.imageUrl,
    this.size = 32,
  });

  final String email;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = email.isEmpty ? null : email[0].toUpperCase();
    final fallback = Center(
      child: initial == null
          ? Icon(PhosphorIconsFill.user, size: size * 0.52)
          : Text(
              initial,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.colors.primary,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.primaryHighlight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.primaryMuted),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: imageUrl == null
            ? fallback
            : Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

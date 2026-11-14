import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/account/account_service.dart';
import '../../theme/theme.dart';

/// The signed-in account as a round badge: the first letter of its name or
/// address on the accent. With no [user], an empty silhouette.
///
/// One widget for the corner of the machine list, the settings row and the
/// account screen, so the three always show the same person the same way.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.user,
    this.size = AppTheme.icon28,
    this.anonymize = false,
  });

  final AccountUser? user;
  final double size;

  /// Shows a dot instead of the letter, as everything that names the user
  /// does while the screen is anonymized.
  final bool anonymize;

  /// The letter that stands for [user]: the first of their name or address.
  static String initialOf(AccountUser user) {
    final source = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email ?? '').trim();
    return source.isEmpty ? '?' : source.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = this.user;
    if (user == null) {
      return Icon(
        PhosphorIconsRegular.userCircle,
        size: size,
        color: colors.textSecondary,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
      child: Text(
        anonymize ? '•' : initialOf(user),
        style: TextStyle(
          color: colors.onPrimary,
          fontSize: size * 0.46,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

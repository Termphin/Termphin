import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/account/account_photos.dart';
import '../../services/account/account_service.dart';
import '../../theme/theme.dart';

/// The signed-in account as a round badge: its Google or GitHub picture,
/// or the first letter of its name or address on the accent until the
/// picture is there or when there is none. With no [user], an empty
/// silhouette.
///
/// One widget for the corner of the machine list, the settings row and the
/// account screen, so the three always show the same person the same way.
class AccountAvatar extends StatefulWidget {
  const AccountAvatar({
    super.key,
    required this.user,
    this.size = AppTheme.icon28,
    this.anonymize = false,
    this.photos,
  });

  final AccountUser? user;
  final double size;

  /// Shows a dot instead of the letter or the picture, as everything that
  /// names the user does while the screen is anonymized.
  final bool anonymize;

  /// Stands in for [AccountPhotos.instance] in tests.
  final AccountPhotos? photos;

  /// The letter that stands for [user]: the first of their name or address.
  static String initialOf(AccountUser user) {
    final source = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email ?? '').trim();
    return source.isEmpty ? '?' : source.characters.first.toUpperCase();
  }

  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<AccountAvatar> {
  String? _url;
  File? _photo;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(AccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  /// Fetches the picture of the current user, once per address.
  void _follow() {
    final url = widget.user?.photoUrl;
    if (url == _url) return;
    _url = url;
    _photo = null;
    if (url == null) return;
    (widget.photos ?? AccountPhotos.instance).fileFor(url).then((file) {
      if (mounted && _url == url && file != null) {
        setState(() => _photo = file);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = widget.user;
    final size = widget.size;
    if (user == null) {
      return Icon(
        PhosphorIconsRegular.userCircle,
        size: size,
        color: colors.textSecondary,
      );
    }
    final photo = _photo;
    if (photo != null && !widget.anonymize) {
      return ClipOval(
        child: Image.file(
          photo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _letter(colors, user),
        ),
      );
    }
    return _letter(colors, user);
  }

  Widget _letter(AppColors colors, AccountUser user) {
    final size = widget.size;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
      child: Text(
        widget.anonymize ? '•' : AccountAvatar.initialOf(user),
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

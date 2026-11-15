import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/sign_in_brands.dart';
import '../../theme/theme.dart';

/// "Continue with Google" as Google's branding guidelines draw it: the
/// four-colour G on a near-black or white pill with a grey outline, by the
/// theme, the mark and the words centred together.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    return _BrandButton(
      label: label,
      onPressed: onPressed,
      fill: dark
          ? SignInBrandColors.googleDarkFill
          : SignInBrandColors.googleLightFill,
      stroke: dark
          ? SignInBrandColors.googleDarkStroke
          : SignInBrandColors.googleLightStroke,
      text: dark
          ? SignInBrandColors.googleDarkText
          : SignInBrandColors.googleLightText,
      logo: SvgPicture.string(
        kGoogleLogoSvg,
        width: AppTheme.icon20,
        height: AppTheme.icon20,
      ),
    );
  }
}

/// "Continue with Apple" as Apple's guidelines draw it: white on a dark
/// screen, black on a light one, the Apple mark before the words.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    final text = dark
        ? SignInBrandColors.appleOnDarkText
        : SignInBrandColors.appleOnLightText;
    return _BrandButton(
      label: label,
      onPressed: onPressed,
      fill: dark
          ? SignInBrandColors.appleOnDarkFill
          : SignInBrandColors.appleOnLightFill,
      stroke: null,
      text: text,
      logo: Icon(
        PhosphorIconsFill.appleLogo,
        size: AppTheme.icon20,
        color: text,
      ),
    );
  }
}

/// "Continue with GitHub": GitHub's mark in its own colours, white on a
/// dark screen and near-black on a light one.
class GitHubSignInButton extends StatelessWidget {
  const GitHubSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    final text = dark
        ? SignInBrandColors.githubOnDarkText
        : SignInBrandColors.githubOnLightText;
    return _BrandButton(
      label: label,
      onPressed: onPressed,
      fill: dark
          ? SignInBrandColors.githubOnDarkFill
          : SignInBrandColors.githubOnLightFill,
      stroke: null,
      text: text,
      logo: Icon(
        PhosphorIconsFill.githubLogo,
        size: AppTheme.icon20,
        color: text,
      ),
    );
  }
}

class _BrandButton extends StatelessWidget {
  const _BrandButton({
    required this.label,
    required this.onPressed,
    required this.fill,
    required this.stroke,
    required this.text,
    required this.logo,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color fill;
  final Color? stroke;
  final Color text;
  final Widget logo;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      side: stroke == null
          ? BorderSide.none
          : BorderSide(color: stroke!, width: AppTheme.hairline),
    );
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: fill,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: AppTheme.space48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                logo,
                const SizedBox(width: AppTheme.space10),
                Text(
                  label,
                  style: TextStyle(
                    color: text,
                    fontSize: AppTheme.font15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

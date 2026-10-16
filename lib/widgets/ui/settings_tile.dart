import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// What sits at the end of a [SettingsTile].
enum SettingsTileTrailing {
  /// A caret: the row opens another screen inside the app.
  chevron,

  /// An arrow out of a box: the row leaves the app for a browser or a store.
  external,

  /// Nothing: the row only shows information, or acts in place.
  none,
}

/// A row in a settings card: optional [icon] or [leading], [title], optional
/// [subtitle], and [trailingWidget] or [trailing] hint about where tapping it
/// goes.
///
/// Give [destination] to open a screen, or [onTap] for anything else; with
/// neither the row is not tappable. Rows that act in place rather than lead
/// somewhere colour their [icon] with [iconColor]; [titleTrailing] sits right
/// after the title, for a badge or an info button.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing = SettingsTileTrailing.chevron,
    this.trailingWidget,
    this.destination,
    this.onTap,
    this.iconColor,
    this.titleTrailing,
    this.dense = false,
    this.contentPadding,
  }) : assert(destination == null || onTap == null),
       assert(icon == null || leading == null);

  final String title;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final SettingsTileTrailing trailing;
  final Widget? trailingWidget;
  final Widget Function()? destination;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Widget? titleTrailing;

  /// Packs the row for a card holding several of them: a smaller title and
  /// the small body style for the subtitle.
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final destination = this.destination;
    final tap = destination != null
        ? () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => destination()),
          )
        : onTap;
    return ListTile(
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: AppTheme.space14),
      leading:
          leading ??
          (icon == null
              ? null
              : Icon(icon, color: iconColor ?? context.colors.textSecondary)),
      title: _title(title, titleTrailing, dense),
      subtitle: _subtitle(context, subtitle, dense),
      trailing:
          trailingWidget ??
          switch (trailing) {
            SettingsTileTrailing.chevron => Icon(
              PhosphorIconsFill.caretRight,
              color: context.colors.textTertiary,
            ),
            SettingsTileTrailing.external => Icon(
              PhosphorIconsFill.arrowSquareOut,
              color: context.colors.textTertiary,
            ),
            SettingsTileTrailing.none => null,
          },
      onTap: tap,
    );
  }
}

/// A switch row in a settings card: optional [icon], [title], optional
/// [subtitle], and the switch itself. [titleTrailing] sits right after the
/// title, for a badge or an info button.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.titleTrailing,
    this.dense = false,
    this.contentPadding,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  /// Overrides the icon's secondary grey, e.g. a warning tint while a switch
  /// that exports credentials is on.
  final Color? iconColor;
  final String? subtitle;
  final Widget? titleTrailing;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: AppTheme.space14),
      secondary: icon == null
          ? null
          : Icon(icon, color: iconColor ?? context.colors.textSecondary),
      title: _title(title, titleTrailing, dense),
      subtitle: _subtitle(context, subtitle, dense),
      value: value,
      activeThumbColor: context.colors.primary,
      onChanged: onChanged,
    );
  }
}

/// A checkbox row in a settings card: optional [icon], [title], optional
/// [subtitle], and the checkbox itself. [titleTrailing] sits right after the
/// title, for a badge or an info button.
class SettingsCheckboxTile extends StatelessWidget {
  const SettingsCheckboxTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.titleTrailing,
    this.dense = false,
    this.contentPadding,
    this.controlAffinity = ListTileControlAffinity.platform,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;
  final Widget? titleTrailing;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity controlAffinity;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: AppTheme.space14),
      secondary: icon == null
          ? null
          : Icon(icon, color: context.colors.textSecondary),
      title: _title(title, titleTrailing, dense),
      subtitle: _subtitle(context, subtitle, dense),
      value: value,
      activeColor: context.colors.primary,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      controlAffinity: controlAffinity,
    );
  }
}

Widget _title(String title, Widget? trailing, bool dense) {
  final text = Text(
    title,
    style: dense ? const TextStyle(fontSize: AppTheme.font14) : null,
  );
  return trailing == null
      ? text
      : Row(
          children: [
            Flexible(child: text),
            trailing,
          ],
        );
}

Widget? _subtitle(BuildContext context, String? subtitle, bool dense) =>
    subtitle == null
    ? null
    : Text(
        subtitle,
        style:
            (dense
                    ? Theme.of(context).textTheme.bodySmall
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(color: context.colors.textTertiary),
      );

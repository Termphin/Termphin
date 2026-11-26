import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import 'section_navigator.dart';

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
/// neither the row is not tappable. A [destination] opens through
/// `pushAppPage` as a window, titled [title], so a desktop keeps the settings
/// list in view behind it. Rows that act in place rather than lead
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
        ? () => pushAppPage<void>(
            context,
            window: true,
            title: title,
            builder: (_) => destination(),
          )
        : onTap;
    return ListTile(
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: AppTheme.space14),
      leading: leading,
      title: _title(
        context,
        title,
        titleTrailing,
        dense,
        icon: icon,
        iconColor: iconColor,
      ),
      subtitle: _subtitle(context, subtitle, dense),
      trailing:
          trailingWidget ??
          switch (trailing) {
            SettingsTileTrailing.chevron => Icon(
              PhosphorIconsRegular.caretRight,
              size: AppTheme.icon18,
              color: context.colors.textTertiary,
            ),
            SettingsTileTrailing.external => Icon(
              PhosphorIconsRegular.arrowSquareOut,
              size: AppTheme.icon18,
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
/// title, for a badge or an info button; [below] goes under the subtitle, for
/// something to show rather than say.
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
    this.below,
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
  final Widget? below;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final below = this.below;
    final text = _subtitle(context, subtitle, dense);
    return SwitchListTile(
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: AppTheme.space14),
      title: _title(
        context,
        title,
        titleTrailing,
        dense,
        icon: icon,
        iconColor: iconColor,
      ),
      subtitle: below == null
          ? text
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?text,
                const SizedBox(height: AppTheme.space8),
                below,
              ],
            ),
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
      title: _title(context, title, titleTrailing, dense, icon: icon),
      subtitle: _subtitle(context, subtitle, dense),
      value: value,
      activeColor: context.colors.primary,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      controlAffinity: controlAffinity,
    );
  }
}

/// The row's title, with its [icon] small and in line before it, so the
/// subtitle below runs the card's full width instead of hanging under an
/// icon column.
Widget _title(
  BuildContext context,
  String title,
  Widget? trailing,
  bool dense, {
  IconData? icon,
  Color? iconColor,
}) {
  final text = Text(
    title,
    style: dense ? const TextStyle(fontSize: AppTheme.font14) : null,
  );
  if (icon == null && trailing == null) return text;
  return Row(
    children: [
      if (icon != null) ...[
        Icon(
          icon,
          size: dense ? AppTheme.icon14 : AppTheme.icon16,
          color: iconColor ?? context.colors.textSecondary,
        ),
        const SizedBox(width: AppTheme.space8),
      ],
      Flexible(child: text),
      ?trailing,
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

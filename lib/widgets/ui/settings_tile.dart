import 'package:flutter/material.dart';
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

/// A row in a settings card: optional [icon], [title], optional [subtitle],
/// and a [trailing] hint about where tapping it goes.
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
    this.subtitle,
    this.trailing = SettingsTileTrailing.chevron,
    this.destination,
    this.onTap,
    this.iconColor,
    this.titleTrailing,
  }) : assert(destination == null || onTap == null);

  final String title;
  final IconData? icon;
  final String? subtitle;
  final SettingsTileTrailing trailing;
  final Widget Function()? destination;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Widget? titleTrailing;

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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: icon == null
          ? null
          : Icon(icon, color: iconColor ?? context.colors.textSecondary),
      title: _title(title, titleTrailing),
      subtitle: _subtitle(context, subtitle),
      trailing: switch (trailing) {
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
/// title, for a badge or an info button; [below] goes under the subtitle, for
/// something to show rather than say.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.titleTrailing,
    this.below,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;
  final Widget? titleTrailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final below = this.below;
    final text = _subtitle(context, subtitle);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      secondary: icon == null
          ? null
          : Icon(icon, color: context.colors.textSecondary),
      title: _title(title, titleTrailing),
      subtitle: below == null
          ? text
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [?text, const SizedBox(height: 8), below],
            ),
      value: value,
      activeThumbColor: context.colors.primary,
      onChanged: onChanged,
    );
  }
}

Widget _title(String title, Widget? trailing) => trailing == null
    ? Text(title)
    : Row(
        children: [
          Flexible(child: Text(title)),
          trailing,
        ],
      );

Widget? _subtitle(BuildContext context, String? subtitle) => subtitle == null
    ? null
    : Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.colors.textTertiary),
      );

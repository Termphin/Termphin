import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';
import 'app_badge.dart';

/// Reusable section or group header row.
///
/// Displays a section or group title on the left, optional count badge and
/// middle elements, and actions (such as an inline Add button) aligned to the right.
/// Used for primary list sections ("All machines", "All keys", "All snippets")
/// and future group headers.
class ListSectionHeader extends StatelessWidget {
  const ListSectionHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.count,
    this.middle,
    this.actions = const [],
    this.onAdd,
    this.addTooltip,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.space16,
      vertical: AppTheme.space4,
    ),
  }) : assert(
         title != null || titleWidget != null,
         'Either title or titleWidget must be provided',
       );

  /// Helper returning a [SliverToBoxAdapter] wrapping a [ListSectionHeader].
  static Widget sliver({
    Key? key,
    String? title,
    Widget? titleWidget,
    int? count,
    Widget? middle,
    List<Widget> actions = const [],
    VoidCallback? onAdd,
    String? addTooltip,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.space16,
      vertical: AppTheme.space4,
    ),
  }) {
    return SliverToBoxAdapter(
      key: key,
      child: ListSectionHeader(
        title: title,
        titleWidget: titleWidget,
        count: count,
        middle: middle,
        actions: actions,
        onAdd: onAdd,
        addTooltip: addTooltip,
        padding: padding,
      ),
    );
  }

  /// The text title of the section (e.g. "All machines").
  final String? title;

  /// Custom widget for the title, overriding [title] if provided.
  final Widget? titleWidget;

  /// Optional item count, rendered as a pill [CountBadge] next to the title.
  final int? count;

  /// Optional middle content rendered between title/badge and right actions.
  final Widget? middle;

  /// Action widgets aligned to the right edge.
  final List<Widget> actions;

  /// Optional callback to show a standard inline Add icon button.
  final VoidCallback? onAdd;

  /// Tooltip for the inline Add button.
  final String? addTooltip;

  /// Insets around the header row.
  final EdgeInsetsGeometry padding;

  /// The compact icon button every header action uses, so a group header's
  /// extra buttons and the add button share one size and density.
  static Widget action({
    Key? key,
    required Widget icon,
    required String? tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      iconSize: AppTheme.icon20,
      color: color,
      visualDensity: VisualDensity.compact,
      icon: icon,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveActions = <Widget>[
      ...actions,
      if (onAdd != null)
        action(
          icon: const Icon(PhosphorIconsRegular.plus),
          tooltip: addTooltip,
          onPressed: onAdd,
          color: context.colors.primary,
        ),
    ];

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          titleWidget ??
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
          if (count != null) ...[
            const SizedBox(width: AppTheme.space8),
            AppBadge.count(count!),
          ],
          if (middle != null) ...[
            const SizedBox(width: AppTheme.space8),
            middle!,
          ],
          const Spacer(),
          ...effectiveActions,
        ],
      ),
    );
  }
}
